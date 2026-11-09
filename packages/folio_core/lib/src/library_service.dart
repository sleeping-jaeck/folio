import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'epub_metadata.dart';
import 'folder_access.dart';
import 'library_store.dart';
import 'models.dart';

/// Owns the local library: app-private books, indexed folders, progress and
/// bookmarks. Everything here works offline.
class LibraryService extends ChangeNotifier {
  LibraryService._(this._store, this._folders, this.rootDir);

  final LibraryStore _store;
  final FolderAccess _folders;

  /// App-private support directory. Books, covers and the reader cache live
  /// under it so the reader WebView can serve them.
  final Directory rootDir;

  List<Book> _books = const [];
  List<LibraryFolder> _libraryFolders = const [];
  bool _scanning = false;

  List<Book> get books => _books;
  List<LibraryFolder> get folders => _libraryFolders;
  bool get scanning => _scanning;

  Directory get booksDir => Directory(p.join(rootDir.path, 'books'));
  Directory get coversDir => Directory(p.join(rootDir.path, 'covers'));
  Directory get readerCacheDir => Directory(p.join(rootDir.path, 'reader_cache'));
  Directory get tempDir => Directory(p.join(rootDir.path, 'tmp'));

  static Future<LibraryService> open(FolderAccess folders) async {
    final root = await getApplicationSupportDirectory();
    final store = await LibraryStore.open(root.path);
    final service = LibraryService._(store, folders, root);
    for (final d in [service.booksDir, service.coversDir, service.readerCacheDir, service.tempDir]) {
      await d.create(recursive: true);
    }
    await service.reload();
    return service;
  }

  Future<void> reload() async {
    _books = await _store.books();
    _libraryFolders = await _store.folders();
    notifyListeners();
  }

  // ---- Local (app-private) books -------------------------------------------

  /// Moves a finished file into the library. [file] must already be under
  /// [rootDir] (for example a completed download in [tempDir]).
  Future<Book> addLocalFile(File file, {String? source, String? displayName}) async {
    final meta = await readEpubMetadata(file, fallbackName: displayName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = File(p.join(booksDir.path, '$stamp${_slug(meta.title)}.epub'));
    final moved = await file.rename(target.path);
    final cover = await _saveCover(meta, 'b$stamp');
    final id = await _store.insertBook({
      'title': meta.title,
      'author': meta.authors.join(', '),
      'kind': BookKind.local.name,
      'file_path': moved.path,
      'cover_path': cover,
      'size': await moved.length(),
      'modified': stamp,
      'added_at': stamp,
      'source': source,
    });
    await reload();
    return (await _store.book(id))!;
  }

  /// Copies a single picked or shared document into app-private storage.
  Future<Book> importDocument(String docUri) async {
    final tmp = File(p.join(tempDir.path, 'import_${DateTime.now().microsecondsSinceEpoch}.epub'));
    await _folders.copyToFile(docUri, tmp.path);
    return addLocalFile(tmp, source: 'Imported');
  }

  /// Opens the system file picker and imports the chosen EPUB.
  Future<Book?> pickAndImport() async {
    final uri = await _folders.pickEpubFile();
    if (uri == null) return null;
    return importDocument(uri);
  }

  // ---- Library folders ------------------------------------------------------

  Future<LibraryFolder?> addFolder() async {
    final picked = await _folders.pickFolder();
    if (picked == null) return null;
    await _store.addFolder(picked.uri, picked.name);
    await reload();
    await rescan();
    return _libraryFolders.firstWhere((f) => f.uri == picked.uri);
  }

  Future<void> removeFolder(LibraryFolder folder) async {
    for (final b in await _store.booksInFolder(folder.uri)) {
      await _deleteCover(b);
    }
    await _store.deleteBooksInFolder(folder.uri);
    await _store.removeFolder(folder.uri);
    await _folders.releaseFolder(folder.uri);
    await reload();
  }

  /// Rescans every library folder: adds new EPUBs, refreshes changed ones and
  /// drops books whose files are gone. Files are never copied permanently.
  Future<void> rescan() async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    try {
      for (final folder in await _store.folders()) {
        if (!await _folders.hasPermission(folder.uri)) continue;
        await _scanFolder(folder);
      }
    } finally {
      _scanning = false;
      await reload();
    }
  }

  Future<void> _scanFolder(LibraryFolder folder) async {
    final files = await _folders.listEpubs(folder.uri);
    final existing = {
      for (final b in await _store.booksInFolder(folder.uri)) b.docUri!: b,
    };
    final seen = <String>{};
    for (final f in files) {
      seen.add(f.uri);
      final known = existing[f.uri];
      if (known != null && known.size == f.size && known.modified == f.modified) {
        continue;
      }
      final tmp = File(p.join(tempDir.path, 'scan.epub'));
      try {
        await _folders.copyToFile(f.uri, tmp.path);
        final meta = await readEpubMetadata(tmp, fallbackName: f.name);
        final now = DateTime.now().millisecondsSinceEpoch;
        if (known != null) await _deleteCover(known);
        final cover = await _saveCover(meta, 'f$now');
        final values = {
          'title': meta.title,
          'author': meta.authors.join(', '),
          'cover_path': cover,
          'size': f.size,
          'modified': f.modified,
        };
        if (known != null) {
          await _store.updateBook(known.id, values);
        } else {
          await _store.insertBook({
            ...values,
            'kind': BookKind.folder.name,
            'doc_uri': f.uri,
            'folder_uri': folder.uri,
            'added_at': now,
            'source': folder.name,
          });
        }
      } on Exception catch (e) {
        debugPrint('Folio: skipped ${f.name}: $e');
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }
    for (final gone in existing.values.where((b) => !seen.contains(b.docUri))) {
      await _deleteCover(gone);
      await _store.deleteBook(gone.id);
    }
  }

  // ---- Reading --------------------------------------------------------------

  /// Returns a file under [rootDir] the reader can open. Folder books are
  /// copied into the reader cache for the duration of the reading session.
  Future<File> prepareForReading(Book book) async {
    await _store.updateBook(book.id, {'last_opened': DateTime.now().millisecondsSinceEpoch});
    if (book.kind == BookKind.local) return File(book.filePath!);
    await clearReaderCache();
    final target = File(p.join(readerCacheDir.path, 'book_${book.id}.epub'));
    await _folders.copyToFile(book.docUri!, target.path);
    return target;
  }

  Future<void> clearReaderCache() async {
    await for (final e in readerCacheDir.list()) {
      await e.delete(recursive: true);
    }
  }

  Future<void> saveProgress(int bookId, {required String cfi, required double progress}) =>
      _store.updateBook(bookId, {'last_cfi': cfi, 'progress': progress});

  Future<void> removeBook(Book book) async {
    if (book.kind == BookKind.local && book.filePath != null) {
      final f = File(book.filePath!);
      if (await f.exists()) await f.delete();
    }
    await _deleteCover(book);
    await _store.deleteBook(book.id);
    await reload();
  }

  Future<List<Bookmark>> bookmarks(int bookId) => _store.bookmarks(bookId);

  Future<void> addBookmark(int bookId, String cfi, String label, double progress) =>
      _store.addBookmark(bookId, cfi, label, progress);

  Future<void> deleteBookmark(int id) => _store.deleteBookmark(id);

  // ---- Helpers --------------------------------------------------------------

  Future<String?> _saveCover(EpubMetadata meta, String key) async {
    final bytes = meta.cover;
    if (bytes == null || bytes.isEmpty) return null;
    final ext = (meta.coverExtension ?? '.jpg').isEmpty ? '.jpg' : meta.coverExtension!;
    final f = File(p.join(coversDir.path, '$key$ext'));
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<void> _deleteCover(Book b) async {
    if (b.coverPath == null) return;
    final f = File(b.coverPath!);
    if (await f.exists()) await f.delete();
  }

  static String _slug(String title) {
    final s = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final trimmed = s.length > 40 ? s.substring(0, 40) : s;
    return trimmed.isEmpty ? '' : '-$trimmed';
  }
}
