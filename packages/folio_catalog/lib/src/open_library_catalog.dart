import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_source.dart';
import 'models.dart';

/// Open Library search restricted to public (non-lending) ebooks. Files are
/// downloaded from Internet Archive items that are not access-restricted.
class OpenLibraryCatalog extends CatalogSource {
  OpenLibraryCatalog({http.Client? client}) : _client = client ?? http.Client();

  static final _searchBase = Uri.parse('https://openlibrary.org/search.json');
  static const _fields = 'key,title,author_name,cover_i,ia,ebook_access';
  static const _headers = {'User-Agent': 'Folio/0.1 (personal ebook reader)'};

  final http.Client _client;

  @override
  String get id => 'openlibrary';
  @override
  String get name => 'Open Library';

  @override
  Future<CatalogPage> root() =>
      _query('subject:"Classic Literature"', title: 'Public domain classics');

  @override
  Future<CatalogPage> open(Uri feedUrl) async {
    final res = await _getJson(feedUrl);
    return _pageFrom(res, title: 'Open Library', url: feedUrl);
  }

  @override
  Future<CatalogPage> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return root();
    return _query(q, title: 'Results for "$q"');
  }

  @override
  Future<Uri?> resolveDownloadUrl(CatalogEntry entry) async {
    final ids = (entry.extra['ia'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort((a, b) => _iaRank(a).compareTo(_iaRank(b)));
    for (final ia in ids.take(8)) {
      final meta = await _getJson(Uri.parse('https://archive.org/metadata/$ia'));
      final metadata = meta['metadata'];
      if (metadata is Map && metadata['access-restricted-item'] == 'true') {
        continue;
      }
      final files = meta['files'];
      if (files is! List) continue;
      for (final f in files) {
        if (f is Map && '${f['name']}'.toLowerCase().endsWith('.epub')) {
          return Uri.parse(
            'https://archive.org/download/$ia/${Uri.encodeComponent('${f['name']}')}',
          );
        }
      }
    }
    return null;
  }

  /// Items mirrored from Project Gutenberg are reliably public; modern scans
  /// (`0000` identifiers) are usually lending-only.
  int _iaRank(String id) {
    if (id.endsWith('gut')) return 0;
    if (id.contains('librivox')) return 9;
    if (id.contains('0000')) return 5;
    return 2;
  }

  Future<CatalogPage> _query(String q, {required String title}) async {
    final url = _searchBase.replace(queryParameters: {
      'q': q,
      'ebook_access': 'public',
      'fields': _fields,
      'limit': '40',
    });
    final res = await _getJson(url);
    return _pageFrom(res, title: title, url: url);
  }

  CatalogPage _pageFrom(Map<String, dynamic> res,
      {required String title, required Uri url}) {
    final docs = (res['docs'] as List?) ?? const [];
    final entries = <CatalogEntry>[];
    for (final d in docs.whereType<Map>()) {
      if (d['ebook_access'] != 'public') continue;
      final ia = (d['ia'] as List?)?.whereType<String>().toList() ?? const [];
      if (ia.isEmpty) continue;
      final cover = d['cover_i'];
      entries.add(CatalogEntry(
        id: '${d['key']}',
        title: '${d['title'] ?? 'Untitled'}',
        authors: (d['author_name'] as List?)?.whereType<String>().toList() ??
            const [],
        thumbnail: cover is int
            ? Uri.parse('https://covers.openlibrary.org/b/id/$cover-M.jpg')
            : null,
        extra: {'ia': ia.join(',')},
      ));
    }
    return CatalogPage(title: title, entries: entries, url: url);
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
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
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw CatalogException('Unexpected response from ${url.host}');
    }
    return decoded;
  }
}
