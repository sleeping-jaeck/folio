import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite metadata for books, bookmarks and library folders.
class LibraryStore {
  LibraryStore._(this._db);

  final Database _db;

  static Future<LibraryStore> open(String directory) async {
    final db = await openDatabase(
      p.join(directory, 'folio.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            kind TEXT NOT NULL,
            file_path TEXT,
            doc_uri TEXT UNIQUE,
            folder_uri TEXT,
            cover_path TEXT,
            size INTEGER NOT NULL DEFAULT 0,
            modified INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL,
            last_opened INTEGER,
            progress REAL NOT NULL DEFAULT 0,
            last_cfi TEXT,
            source TEXT
          )''');
        await db.execute('''
          CREATE TABLE bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            cfi TEXT NOT NULL,
            label TEXT NOT NULL,
            progress REAL NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE folders (
            uri TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            added_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX books_folder ON books(folder_uri)');
      },
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return LibraryStore._(db);
  }

  Future<List<Book>> books() async {
    final rows = await _db.query('books',
        orderBy: 'COALESCE(last_opened, 0) DESC, added_at DESC');
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> book(int id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromRow(rows.single);
  }

  Future<int> insertBook(Map<String, Object?> values) =>
      _db.insert('books', values);

  Future<void> updateBook(int id, Map<String, Object?> values) =>
      _db.update('books', values, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteBook(int id) =>
      _db.delete('books', where: 'id = ?', whereArgs: [id]);

  Future<List<Book>> booksInFolder(String folderUri) async {
    final rows = await _db
        .query('books', where: 'folder_uri = ?', whereArgs: [folderUri]);
    return rows.map(Book.fromRow).toList();
  }

  Future<void> deleteBooksInFolder(String folderUri) =>
      _db.delete('books', where: 'folder_uri = ?', whereArgs: [folderUri]);

  Future<List<LibraryFolder>> folders() async {
    final rows = await _db.query('folders', orderBy: 'added_at');
    return rows.map(LibraryFolder.fromRow).toList();
  }

  Future<void> addFolder(String uri, String name) => _db.insert(
        'folders',
        {'uri': uri, 'name': name, 'added_at': _now()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> removeFolder(String uri) =>
      _db.delete('folders', where: 'uri = ?', whereArgs: [uri]);

  Future<List<Bookmark>> bookmarks(int bookId) async {
    final rows = await _db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'progress');
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<int> addBookmark(int bookId, String cfi, String label, double progress) =>
      _db.insert('bookmarks', {
        'book_id': bookId,
        'cfi': cfi,
        'label': label,
        'progress': progress,
        'created_at': _now(),
      });

  Future<void> deleteBookmark(int id) =>
      _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
