import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thrown when a download is cancelled through its [CancelToken].
class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Streams [url] into [target]. Writes to a `.part` file first and renames it
/// on success, so a half-finished file never appears in the library.
Future<File> downloadToFile(
  Uri url,
  File target, {
  void Function(int received, int? total)? onProgress,
  CancelToken? cancel,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final part = File('${target.path}.part');
  IOSink? sink;
  try {
    final req = http.Request('GET', url)
      ..headers['User-Agent'] = 'Folio/0.1 (personal ebook reader)';
    final res = await c.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw CatalogException('HTTP ${res.statusCode} downloading ${url.host}');
    }
    await part.parent.create(recursive: true);
    sink = part.openWrite();
    var received = 0;
    await for (final chunk in res.stream) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, res.contentLength);
    }
    await sink.close();
    sink = null;
    if (await target.exists()) await target.delete();
    return await part.rename(target.path);
  } catch (_) {
    await sink?.close();
    if (await part.exists()) await part.delete();
    rethrow;
  } finally {
    if (client == null) c.close();
  }
}
