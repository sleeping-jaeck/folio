import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../services/download_queue.dart';
import 'reader_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = Services.of(context).downloads;
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final tasks = queue.tasks;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [
              if (tasks.any((t) => !t.isActive))
                TextButton(onPressed: queue.clearFinished, child: const Text('Clear finished')),
            ],
          ),
          body: tasks.isEmpty
              ? const Center(child: Text('Books you download from Browse appear here.'))
              : ListView.separated(
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _TaskTile(task: tasks[i], queue: queue),
                ),
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.queue});

  final DownloadTask task;
  final DownloadQueue queue;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (task.status) {
      DownloadStatus.queued => const Text('Waiting'),
      DownloadStatus.resolving => const Text('Finding the EPUB file'),
      DownloadStatus.downloading => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: task.fraction),
            const SizedBox(height: 4),
            Text('${(task.received / 1024 / 1024).toStringAsFixed(1)} MB'
                '${task.total != null ? ' of ${(task.total! / 1024 / 1024).toStringAsFixed(1)} MB' : ''}'),
          ],
        ),
      DownloadStatus.done => Text('In your library · ${task.source.name}'),
      DownloadStatus.failed => Text(task.error ?? 'Failed', maxLines: 3),
      DownloadStatus.cancelled => const Text('Cancelled'),
    };
    final trailing = switch (task.status) {
      DownloadStatus.done => TextButton(
          onPressed: () => openReader(context, task.book!),
          child: const Text('Read'),
        ),
      DownloadStatus.failed || DownloadStatus.cancelled => IconButton(
          tooltip: 'Retry',
          icon: const Icon(Icons.refresh),
          onPressed: () => queue.retry(task),
        ),
      _ => IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => queue.cancel(task),
        ),
    };
    return ListTile(
      title: Text(task.entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
