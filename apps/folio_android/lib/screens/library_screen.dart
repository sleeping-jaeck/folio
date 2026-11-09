import 'dart:io';

import 'package:flutter/material.dart';
import 'package:folio_core/folio_core.dart';

import '../services/app_services.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = Services.of(context).library;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Import EPUB',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => _import(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final books = library.books;
          return RefreshIndicator(
            onRefresh: library.rescan,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (library.scanning)
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
                if (books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyLibrary(onImport: () => _import(context)),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: books.length,
                      itemBuilder: (context, i) => _BookTile(book: books[i]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final library = Services.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final book = await library.pickAndImport();
      if (book != null && context.mounted) await openReader(context, book);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Your library is empty', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Add a folder of EPUBs in Settings, import a file, or download from Browse.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onImport,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import EPUB'),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openReader(context, book),
      onLongPress: () => _confirmRemove(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: BookCover(book: book)),
          if (book.progress > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: book.progress, minHeight: 3),
          ],
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          if (book.author.isNotEmpty)
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final library = Services.of(context).library;
    final inFolder = book.kind == BookKind.folder;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "${book.title}"?'),
        content: Text(inFolder
            ? 'It is in a library folder, so it will come back on the next rescan unless you delete the file.'
            : 'The downloaded file will be deleted from Folio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await library.removeBook(book);
  }
}

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Text(
        book.title,
        textAlign: TextAlign.center,
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.expand(
        child: book.coverPath == null
            ? placeholder
            : Image.file(
                File(book.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
