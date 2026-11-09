import 'models.dart';

/// Common interface for every place Folio can browse and download books from.
abstract class CatalogSource {
  String get id;
  String get name;

  /// Whether the source has a usable endpoint. The primary slot is not
  /// configured until the user sets a base URL.
  bool get isConfigured => true;

  Future<CatalogPage> root();
  Future<CatalogPage> open(Uri feedUrl);
  Future<CatalogPage> search(String query);

  /// Picks the EPUB download for an entry, fetching detail feeds if needed.
  Future<Uri?> resolveDownloadUrl(CatalogEntry entry);
}
