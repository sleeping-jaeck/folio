import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:folio_catalog/folio_catalog.dart';
import 'package:folio_core/folio_core.dart';
import 'package:path/path.dart' as p;

enum DownloadStatus { queued, resolving, downloading, done, failed, cancelled }

class DownloadTask {
  DownloadTask({required this.entry, required this.source});

  final CatalogEntry entry;
  final CatalogSource source;
  final cancel = CancelToken();

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int? total;
  String? error;
  Book? book;

  double? get fraction => (total == null || total == 0) ? null : received / total!;
  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.resolving ||
      status == DownloadStatus.downloading;
}

/// Downloads catalog books one at a time and adds them to the library.
class DownloadQueue extends ChangeNotifier {
  DownloadQueue(this._library);

  final LibraryService _library;
  final List<DownloadTask> _tasks = [];
  bool _running = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks.reversed);
  int get activeCount => _tasks.where((t) => t.isActive).length;

  DownloadTask enqueue(CatalogEntry entry, CatalogSource source) {
    final task = DownloadTask(entry: entry, source: source);
    _tasks.add(task);
    notifyListeners();
    _pump();
    return task;
  }

  void retry(DownloadTask task) {
    final fresh = DownloadTask(entry: task.entry, source: task.source);
    _tasks
      ..remove(task)
      ..add(fresh);
    notifyListeners();
    _pump();
  }

  void cancel(DownloadTask task) {
    task.cancel.cancel();
    if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.cancelled;
      notifyListeners();
    }
  }

  void clearFinished() {
    _tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _tasks.where((t) => t.status == DownloadStatus.queued).firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    final tmp = File(p.join(_library.tempDir.path, 'dl_${DateTime.now().microsecondsSinceEpoch}.epub'));
    try {
      task.status = DownloadStatus.resolving;
      notifyListeners();
      final url = await task.source.resolveDownloadUrl(task.entry);
      if (url == null) throw CatalogException('No EPUB download offered for this book.');
      if (task.cancel.isCancelled) throw DownloadCancelled();

      task.status = DownloadStatus.downloading;
      notifyListeners();
      var lastNotify = 0;
      await downloadToFile(url, tmp, cancel: task.cancel, onProgress: (received, total) {
        task
          ..received = received
          ..total = total;
        if (received - lastNotify > 64 * 1024) {
          lastNotify = received;
          notifyListeners();
        }
      });
      task.book = await _library.addLocalFile(
        tmp,
        source: task.source.name,
        displayName: '${task.entry.title}.epub',
      );
      task.status = DownloadStatus.done;
    } on DownloadCancelled {
      task.status = DownloadStatus.cancelled;
    } catch (e) {
      task
        ..status = DownloadStatus.failed
        ..error = '$e';
    } finally {
      if (await tmp.exists()) await tmp.delete();
      notifyListeners();
    }
  }
}
