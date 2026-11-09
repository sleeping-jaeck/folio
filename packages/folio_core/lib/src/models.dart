/// Where a book's file lives.
enum BookKind {
  /// Copied into app-private storage (imported or downloaded).
  local,

  /// Indexed in place inside a user-picked library folder.
  folder,
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.kind,
    this.filePath,
    this.docUri,
    this.folderUri,
    this.coverPath,
    this.size = 0,
    this.modified = 0,
    required this.addedAt,
    this.lastOpened,
    this.progress = 0,
    this.lastCfi,
    this.source,
  });

  final int id;
  final String title;
  final String author;
  final BookKind kind;

  /// Absolute path for [BookKind.local] books.
  final String? filePath;

  /// Storage Access Framework document URI for [BookKind.folder] books.
  final String? docUri;
  final String? folderUri;

  final String? coverPath;
  final int size;
  final int modified;
  final int addedAt;
  final int? lastOpened;

  /// Reading progress from 0 to 1.
  final double progress;

  /// EPUB CFI of the last read position.
  final String? lastCfi;

  /// Catalog or import origin, for display only.
  final String? source;

  factory Book.fromRow(Map<String, Object?> r) => Book(
        id: r['id'] as int,
        title: r['title'] as String,
        author: r['author'] as String,
        kind: BookKind.values.byName(r['kind'] as String),
        filePath: r['file_path'] as String?,
        docUri: r['doc_uri'] as String?,
        folderUri: r['folder_uri'] as String?,
        coverPath: r['cover_path'] as String?,
        size: (r['size'] as int?) ?? 0,
        modified: (r['modified'] as int?) ?? 0,
        addedAt: r['added_at'] as int,
        lastOpened: r['last_opened'] as int?,
        progress: ((r['progress'] as num?) ?? 0).toDouble(),
        lastCfi: r['last_cfi'] as String?,
        source: r['source'] as String?,
      );
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.cfi,
    required this.label,
    required this.progress,
    required this.createdAt,
  });

  final int id;
  final int bookId;
  final String cfi;
  final String label;
  final double progress;
  final int createdAt;

  factory Bookmark.fromRow(Map<String, Object?> r) => Bookmark(
        id: r['id'] as int,
        bookId: r['book_id'] as int,
        cfi: r['cfi'] as String,
        label: r['label'] as String,
        progress: ((r['progress'] as num?) ?? 0).toDouble(),
        createdAt: r['created_at'] as int,
      );
}

class LibraryFolder {
  const LibraryFolder({required this.uri, required this.name, required this.addedAt});

  final String uri;
  final String name;
  final int addedAt;

  factory LibraryFolder.fromRow(Map<String, Object?> r) => LibraryFolder(
        uri: r['uri'] as String,
        name: r['name'] as String,
        addedAt: r['added_at'] as int,
      );
}
