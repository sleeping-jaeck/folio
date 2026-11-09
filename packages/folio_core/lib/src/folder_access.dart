/// A folder the user granted access to through the system picker.
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});
  final String uri;
  final String name;
}

/// One `.epub` document found while scanning a folder.
class FolderFile {
  const FolderFile({
    required this.uri,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String uri;
  final String name;
  final int size;
  final int modified;
}

/// Platform access to user-picked folders and documents (Android Storage
/// Access Framework). Implemented by the app over a method channel.
abstract class FolderAccess {
  /// Opens the system folder picker and keeps a persisted read permission.
  Future<PickedFolder?> pickFolder();

  /// Opens the system file picker for a single EPUB.
  Future<String?> pickEpubFile();

  /// Recursively lists `.epub` documents under [treeUri].
  Future<List<FolderFile>> listEpubs(String treeUri);

  /// Copies a document's bytes to [path].
  Future<void> copyToFile(String docUri, String path);

  Future<bool> hasPermission(String treeUri);

  Future<void> releaseFolder(String treeUri);

  /// EPUB opened from a file manager or the share sheet, if one is pending.
  Future<String?> takeIncomingDocument();

  /// Fires when an EPUB is opened from outside while the app is running.
  Stream<String> get incomingDocuments;
}
