import 'catalog_source.dart';
import 'open_library_catalog.dart';
import 'opds_catalog.dart';

const placeholderPrimaryUrl = 'https://example.invalid/opds';

final gutenbergRoot = Uri.parse('https://www.gutenberg.org/ebooks.opds/');

/// Standard Ebooks' full OPDS catalog is limited to Patrons Circle members;
/// the New Releases feed is open to everyone.
final standardEbooksRoot =
    Uri.parse('https://standardebooks.org/feeds/atom/new-releases');

/// Builds the ordered list of sources shown in Browse: the configurable
/// primary slot first, then the built-in extras.
List<CatalogSource> buildSources({required String primaryBaseUrl}) {
  return [
    OpdsCatalog(
      id: 'primary',
      name: 'Primary',
      rootUrl: Uri.tryParse(primaryBaseUrl.trim()),
    ),
    OpdsCatalog(
      id: 'gutenberg',
      name: 'Gutenberg',
      rootUrl: gutenbergRoot,
    ),
    OpdsCatalog(
      id: 'standardebooks',
      name: 'Standard Ebooks',
      rootUrl: standardEbooksRoot,
      searchMode: SearchMode.localFilter,
    ),
    OpenLibraryCatalog(),
  ];
}
