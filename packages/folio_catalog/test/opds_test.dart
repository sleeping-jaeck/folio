import 'package:folio_catalog/folio_catalog.dart';
import 'package:test/test.dart';

const _navFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Books: test</title>
  <link rel="search" type="application/opensearchdescription+xml" href="/osd.xml"/>
  <link rel="next" type="application/atom+xml;profile=opds-catalog" href="/search.opds/?query=test&amp;start_index=26"/>
  <entry>
    <id>https://example.org/ebooks/1.opds</id>
    <title>Sample Book</title>
    <content type="text">Sample Author</content>
    <link type="application/atom+xml;profile=opds-catalog" rel="subsection" href="/ebooks/1.opds"/>
    <link type="image/png" rel="http://opds-spec.org/image/thumbnail" href="data:image/png;base64,AAAA"/>
  </entry>
</feed>''';

const _acqFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
  <title>New</title>
  <entry>
    <id>urn:book:2</id>
    <title>Second Book</title>
    <author><name>Writer, Some</name></author>
    <summary type="text">A short summary.</summary>
    <media:thumbnail url="https://example.org/cover-thumb.jpg"/>
    <link rel="enclosure" type="application/epub+zip" title="Advanced epub" href="https://example.org/b_advanced.epub"/>
    <link rel="enclosure" type="application/epub+zip" title="Recommended compatible epub" href="https://example.org/b.epub"/>
    <link rel="enclosure" type="application/xhtml+xml" title="XHTML" href="https://example.org/single-page"/>
    <link rel="http://opds-spec.org/acquisition" type="application/x-mobipocket-ebook" href="https://example.org/b.azw3"/>
  </entry>
</feed>''';

const _osd = '''<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <Url type="text/html" template="https://example.org/search/?query={searchTerms}"/>
  <Url type="application/atom+xml" template="https://example.org/search.opds/?query={searchTerms}&amp;page={startPage?}"/>
</OpenSearchDescription>''';

void main() {
  final base = Uri.parse('https://example.org/search.opds/?query=test');

  test('navigation entries resolve relative links and skip data URIs', () {
    final page = parseOpdsFeed(_navFeed, base);
    expect(page.title, 'Books: test');
    expect(page.entries, hasLength(1));
    final e = page.entries.single;
    expect(e.isNavigation, isTrue);
    expect(e.navigation.toString(), 'https://example.org/ebooks/1.opds');
    expect(e.detailUrl, e.navigation);
    expect(e.thumbnail, isNull);
    expect(page.nextPage.toString(),
        'https://example.org/search.opds/?query=test&start_index=26');
    expect(page.searchTemplate, 'https://example.org/osd.xml');
  });

  test('acquisition entries collect EPUB enclosures and pick the recommended one', () {
    final page = parseOpdsFeed(_acqFeed, base);
    final e = page.entries.single;
    expect(e.isBook, isTrue);
    expect(e.authors, ['Writer, Some']);
    expect(e.summary, 'A short summary.');
    expect(e.thumbnail.toString(), 'https://example.org/cover-thumb.jpg');
    expect(e.acquisitions, hasLength(3));
    expect(pickEpub(e.acquisitions)!.url.toString(), 'https://example.org/b.epub');
  });

  test('OpenSearch picks the Atom template and fills it', () {
    final template = parseOpenSearchTemplate(_osd)!;
    expect(template, contains('search.opds'));
    expect(fillSearchTemplate(template, 'jane austen'),
        'https://example.org/search.opds/?query=jane+austen&page=1');
  });

  test('primary slot with the placeholder URL is not configured', () {
    final sources = buildSources(primaryBaseUrl: placeholderPrimaryUrl);
    expect(sources.first.id, 'primary');
    expect(sources.first.isConfigured, isFalse);
    expect(sources.skip(1).every((s) => s.isConfigured), isTrue);
  });

  test('non-feed responses raise a CatalogException', () {
    expect(() => parseOpdsFeed('<html></html>', base),
        throwsA(isA<CatalogException>()));
  });
}
