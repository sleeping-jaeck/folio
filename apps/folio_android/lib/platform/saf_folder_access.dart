import 'dart:async';

import 'package:flutter/services.dart';
import 'package:folio_core/folio_core.dart';

/// [FolderAccess] over the `dev.folio/storage` channel in `MainActivity.kt`.
class SafFolderAccess implements FolderAccess {
  SafFolderAccess() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingDocument' && call.arguments is String) {
        _incoming.add(call.arguments as String);
      }
    });
  }

  static const _channel = MethodChannel('dev.folio/storage');
  final _incoming = StreamController<String>.broadcast();

  @override
  Stream<String> get incomingDocuments => _incoming.stream;

  @override
  Future<PickedFolder?> pickFolder() async {
    final res = await _channel.invokeMapMethod<String, Object?>('pickFolder');
    if (res == null) return null;
    return PickedFolder(uri: res['uri'] as String, name: (res['name'] as String?) ?? 'Folder');
  }

  @override
  Future<String?> pickEpubFile() => _channel.invokeMethod<String>('pickEpubFile');

  @override
  Future<List<FolderFile>> listEpubs(String treeUri) async {
    final res = await _channel.invokeListMethod<Map>('listEpubs', {'treeUri': treeUri}) ?? const [];
    return [
      for (final m in res)
        FolderFile(
          uri: m['uri'] as String,
          name: m['name'] as String,
          size: (m['size'] as num).toInt(),
          modified: (m['modified'] as num).toInt(),
        ),
    ];
  }

  @override
  Future<void> copyToFile(String docUri, String path) =>
      _channel.invokeMethod('copyToFile', {'uri': docUri, 'path': path});

  @override
  Future<bool> hasPermission(String treeUri) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'treeUri': treeUri}) ?? false;

  @override
  Future<void> releaseFolder(String treeUri) =>
      _channel.invokeMethod('releaseFolder', {'treeUri': treeUri});

  @override
  Future<String?> takeIncomingDocument() => _channel.invokeMethod<String>('takeIncomingDocument');
}
