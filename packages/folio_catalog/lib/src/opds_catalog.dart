import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'catalog_source.dart';
import 'models.dart';

const _acquisitionRel = 'http://opds-spec.org/acquisition';
const _thumbnailRel = 'http://opds-spec.org/image/thumbnail';
const _imageRel = 'http://opds-spec.org/image';

/// How [OpdsCatalog.search] finds results.
enum SearchMode {
  /// Use the feed's OpenSearch link; fall back to filtering the root feed if
  /// the feed has no search link or the server refuses the request.
  feed,

  /// Always filter the entries of the root feed locally.
  localFilter,
}

/// Generic OPDS 1.x (Atom) catalog client.
class OpdsCatalog extends CatalogSource {
  OpdsCatalog({
    required this.id,
    required this.name,
    required this.rootUrl,
    this.searchMode = SearchMode.feed,
    http.Client? client,
    Map<String, String> headers = const {},
  })  : _client = client ?? http.Client(),
        _headers = {
          'Accept':
              'application/atom+xml;profile=opds-catalog, application/atom+xml;q=0.9, */*;q=0.5',
          'User-Agent': 'Folio/0.1 (personal ebook reader)',
          ...headers,
        };

  @override
  final String id;
  @override
  final String name;
  final Uri? rootUrl;
  final SearchMode searchMode;
  final http.Client _client;
  final Map<String, String> _headers;

  String? _searchTemplate;
  bool _searchResolved = false;
  CatalogPage? _rootCache;

  @override
  bool get isConfigured =>
      rootUrl != null &&
      (rootUrl!.scheme == 'http' || rootUrl!.scheme == 'https') &&
      rootUrl!.host.isNotEmpty &&
      rootUrl!.host != 'example.invalid';

  @override
  Future<CatalogPage> root() async {
    if (!isConfigured) {
      throw CatalogException('No primary source configured.');
    }
    final page = await open(rootUrl!);
    _rootCache = page;
    return page;
  }

  @override
  Future<CatalogPage> open(Uri feedUrl) async {
    final url = _https(feedUrl);
    final body = await _get(url);
    return parseOpdsFeed(body, url);
  }

  /// Android blocks cleartext HTTP, so links to `http://` on a source served
  /// over HTTPS are upgraded. Links to a sibling host on the same domain
  /// (for example a mobile `m.` host) are pinned to the catalog's own host.
  Uri _https(Uri url) {
    final root = rootUrl;
    if (root == null) return url;
    var out = url;
    if (out.scheme == 'http' && root.scheme == 'https') {
      out = out.replace(scheme: 'https');
    }
    if (out.host != root.host && _domain(out.host) == _domain(root.host)) {
      out = out.replace(host: root.host);
    }
    return out;
  }

  static String _domain(String host) {
    final parts = host.split('.');
    return parts.length <= 2
        ? host
        : parts.sublist(parts.length - 2).join('.');
  }

  @override
  Future<CatalogPage> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return root();
    if (searchMode == SearchMode.feed) {
      final template = await _resolveSearchTemplate();
      if (template != null) {
        try {
          return await open(_https(Uri.parse(fillSearchTemplate(template, q))));
        } on CatalogException catch (e) {
          if (!e.message.contains('HTTP 401') &&
              !e.message.contains('HTTP 403')) {
            rethrow;
          }
        }
      }
    }
    return _filterRoot(q);
  }

  @override
  Future<Uri?> resolveDownloadUrl(CatalogEntry entry) async {
    final direct = pickEpub(entry.acquisitions);
    if (direct != null) return direct.url;
    final detail = entry.detailUrl ?? entry.navigation;
    if (detail == null) return null;
    final page = await open(detail);
    for (final e in page.entries) {
      final a = pickEpub(e.acquisitions);
      if (a != null) return a.url;
    }
    return null;
  }

  Future<CatalogPage> _filterRoot(String query) async {
    final rootPage = _rootCache ?? await root();
    final terms = query.toLowerCase().split(RegExp(r'\s+'));
    final matches = rootPage.entries.where((e) {
      final hay = '${e.title} ${e.authorLine} ${e.summary ?? ''}'.toLowerCase();
      return terms.every(hay.contains);
    }).toList();
    return CatalogPage(title: 'Results for "$query"', entries: matches);
  }

  Future<String?> _resolveSearchTemplate() async {
    if (_searchResolved) return _searchTemplate;
    final rootPage = _rootCache ?? await root();
    final link = rootPage.searchTemplate;
    if (link == null) {
      _searchResolved = true;
      return null;
    }
    if (link.contains('{searchTerms}')) {
      _searchTemplate = link;
    } else {
      try {
        _searchTemplate =
            parseOpenSearchTemplate(await _get(_https(Uri.parse(link))));
      } on CatalogException {
        _searchTemplate = null;
      }
    }
    _searchResolved = true;
    return _searchTemplate;
  }

  Future<String> _get(Uri url) async {
    final http.Response res;
    try {
      res = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      throw CatalogException('Could not reach ${url.host}: $e');
    }
    if (res.statusCode != 200) {
      throw CatalogException('HTTP ${res.statusCode} from ${url.host}');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}

/// Parses an OPDS 1.x / Atom feed. Relative links are resolved against [base].
CatalogPage parseOpdsFeed(String body, Uri base) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException {
    throw CatalogException('The source did not return an OPDS feed.');
  }
  final feed = doc.rootElement;
  if (feed.localName != 'feed') {
    throw CatalogException('The source did not return an OPDS feed.');
  }

  Uri? nextPage;
  String? search;
  for (final link in _children(feed, 'link')) {
    final rel = link.getAttribute('rel') ?? '';
    final href = link.getAttribute('href');
    if (href == null) continue;
    if (rel == 'next') nextPage = base.resolve(href);
    if (rel == 'search') {
      final type = link.getAttribute('type') ?? '';
      if (search == null || type.contains('atom')) {
        search = href.contains('{searchTerms}')
            ? _resolveTemplate(base, href)
            : base.resolve(href).toString();
      }
    }
  }

  final entries = <CatalogEntry>[];
  for (final entry in _children(feed, 'entry')) {
    final parsed = _parseEntry(entry, base);
    if (parsed != null) entries.add(parsed);
  }

  return CatalogPage(
    title: _text(feed, 'title') ?? 'Catalog',
    entries: entries,
    url: base,
    nextPage: nextPage,
    searchTemplate: search,
  );
}

CatalogEntry? _parseEntry(XmlElement entry, Uri base) {
  final title = _text(entry, 'title');
  if (title == null) return null;

  final authors = _children(entry, 'author')
      .map((a) => _text(a, 'name'))
      .whereType<String>()
      .toList();

  Uri? navigation;
  Uri? thumbnail;
  Uri? image;
  final acquisitions = <Acquisition>[];

  for (final link in _children(entry, 'link')) {
    final rel = link.getAttribute('rel') ?? '';
    final type = link.getAttribute('type') ?? '';
    final href = link.getAttribute('href');
    if (href == null || href.startsWith('data:')) continue;
    final url = base.resolve(href);

    if (rel.startsWith(_acquisitionRel) || rel == 'enclosure') {
      if (type.contains('xhtml') || type.contains('html')) continue;
      acquisitions.add(
        Acquisition(url: url, type: type, title: link.getAttribute('title')),
      );
    } else if (rel == _thumbnailRel) {
      thumbnail = url;
    } else if (rel == _imageRel) {
      image = url;
    } else if (type.contains('profile=opds-catalog') &&
        (rel.isEmpty ||
            rel == 'subsection' ||
            rel == 'alternate' ||
            rel == 'http://opds-spec.org/sort/new' ||
            rel == 'http://opds-spec.org/sort/popular' ||
            rel == 'collection')) {
      navigation ??= url;
    }
  }

  for (final el in entry.childElements) {
    if (el.localName == 'thumbnail') {
      final u = el.getAttribute('url');
      if (u != null) thumbnail ??= base.resolve(u);
    }
  }

  return CatalogEntry(
    id: _text(entry, 'id') ?? navigation?.toString() ?? title,
    title: title,
    authors: authors,
    summary: _summary(entry),
    thumbnail: thumbnail ?? image,
    navigation: navigation,
    acquisitions: acquisitions,
    detailUrl: acquisitions.isEmpty ? navigation : null,
  );
}

/// Picks the best EPUB from a list of acquisitions.
Acquisition? pickEpub(List<Acquisition> acquisitions) {
  final epubs = acquisitions.where((a) => a.isEpub).toList();
  if (epubs.isEmpty) return null;
  int score(Acquisition a) {
    final t = (a.title ?? '').toLowerCase();
    final u = a.url.toString().toLowerCase();
    var s = 0;
    if (t.contains('recommended')) s += 3;
    if (t.contains('epub3') || u.contains('epub3')) s += 2;
    if (t.contains('no images') || u.contains('noimages')) s -= 1;
    if (t.contains('advanced')) s -= 1;
    return s;
  }

  epubs.sort((a, b) => score(b).compareTo(score(a)));
  return epubs.first;
}

/// Reads the Atom search template from an OpenSearch description document.
String? parseOpenSearchTemplate(String body) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException {
    return null;
  }
  String? best;
  var bestScore = -1;
  for (final url in doc.rootElement.childElements) {
    if (url.localName != 'Url') continue;
    final type = url.getAttribute('type') ?? '';
    final template = url.getAttribute('template');
    if (template == null) continue;
    final s = type.contains('profile=opds-catalog')
        ? 3
        : type.startsWith('application/atom+xml')
            ? 2
            : -1;
    if (s > bestScore) {
      best = template;
      bestScore = s;
    }
  }
  return bestScore >= 0 ? best : null;
}

/// Substitutes the query into an OpenSearch template. Optional parameters
/// (`{name?}`) are dropped; `count` and `startPage` get sensible defaults.
String fillSearchTemplate(String template, String query) {
  return template.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) {
    final name = m[1]!;
    if (name == 'searchTerms') return Uri.encodeQueryComponent(query);
    if (name == 'count' || name == 'count?') return '30';
    if (name == 'startPage' || name == 'startPage?') return '1';
    if (name == 'startIndex' || name == 'startIndex?') return '1';
    return '';
  });
}

String _resolveTemplate(Uri base, String href) {
  if (href.startsWith('http://') || href.startsWith('https://')) return href;
  final placeholder = href.replaceAll('{searchTerms}', 'FOLIOSEARCHTERMS');
  return base
      .resolve(placeholder)
      .toString()
      .replaceAll('FOLIOSEARCHTERMS', '{searchTerms}');
}

Iterable<XmlElement> _children(XmlElement parent, String localName) =>
    parent.childElements.where((e) => e.localName == localName);

String? _text(XmlElement parent, String localName) {
  for (final e in _children(parent, localName)) {
    final t = e.innerText.trim();
    if (t.isNotEmpty) return t.replaceAll(RegExp(r'\s+'), ' ');
  }
  return null;
}

String? _summary(XmlElement entry) {
  final raw = _text(entry, 'summary') ?? _text(entry, 'content');
  if (raw == null) return null;
  return raw.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
