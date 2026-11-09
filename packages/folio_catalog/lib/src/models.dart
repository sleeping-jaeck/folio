/// A downloadable file offered by a catalog entry.
class Acquisition {
  const Acquisition({required this.url, required this.type, this.title});

  final Uri url;
  final String type;
  final String? title;

  bool get isEpub => type.startsWith('application/epub+zip');
}

/// One row in a catalog page: either a book or a link to another feed.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.title,
    this.authors = const [],
    this.summary,
    this.thumbnail,
    this.navigation,
    this.acquisitions = const [],
    this.detailUrl,
    this.extra = const {},
  });

  final String id;
  final String title;
  final List<String> authors;
  final String? summary;
  final Uri? thumbnail;

  /// Set when the entry opens another feed instead of being a book.
  final Uri? navigation;

  final List<Acquisition> acquisitions;

  /// Feed that describes this book in more detail (used when a search result
  /// has no direct acquisition link).
  final Uri? detailUrl;

  /// Source-specific data (for example an Internet Archive identifier).
  final Map<String, String> extra;

  bool get isNavigation => navigation != null && acquisitions.isEmpty;
  bool get isBook => !isNavigation;
  String get authorLine => authors.join(', ');
}

/// A page of catalog results.
class CatalogPage {
  const CatalogPage({
    required this.title,
    required this.entries,
    this.url,
    this.nextPage,
    this.searchTemplate,
  });

  final String title;
  final List<CatalogEntry> entries;
  final Uri? url;
  final Uri? nextPage;

  /// URL template with `{searchTerms}`, when the feed advertises search.
  final String? searchTemplate;
}

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;

  @override
  String toString() => message;
}
