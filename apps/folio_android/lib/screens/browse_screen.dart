import 'package:flutter/material.dart';
import 'package:folio_catalog/folio_catalog.dart';

import '../services/app_services.dart';

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ValueListenableBuilder<List<CatalogSource>>(
      valueListenable: services.sources,
      builder: (context, sources, _) => DefaultTabController(
        key: ValueKey(sources),
        length: sources.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Browse'),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final s in sources) Tab(text: s.name)],
            ),
          ),
          body: TabBarView(
            children: [for (final s in sources) _SourceTab(key: ValueKey(s), source: s)],
          ),
        ),
      ),
    );
  }
}

/// One source: search box plus a stack of opened feeds (root, sub-feeds,
/// search results) that the user can navigate back through.
class _SourceTab extends StatefulWidget {
  const _SourceTab({super.key, required this.source});

  final CatalogSource source;

  @override
  State<_SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<_SourceTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  final List<CatalogPage> _stack = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.source.isConfigured) _load(widget.source.root);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(Future<CatalogPage> Function() fetch, {bool replace = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await fetch();
      if (!mounted) return;
      setState(() {
        if (replace) _stack.clear();
        _stack.add(page);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final page = _stack.lastOrNull;
    final next = page?.nextPage;
    if (next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await widget.source.open(next);
      if (!mounted) return;
      setState(() {
        _stack[_stack.length - 1] = CatalogPage(
          title: page!.title,
          entries: [...page.entries, ...more.entries],
          url: page.url,
          nextPage: more.nextPage,
          searchTemplate: page.searchTemplate,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _back() => setState(() {
        _stack.removeLast();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.source.isConfigured) return const _NotConfigured();

    final page = _stack.lastOrNull;
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stack.length > 1) _back();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SearchBar(
              controller: _search,
              hintText: 'Search ${widget.source.name}',
              leading: const Icon(Icons.search),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      _load(widget.source.root, replace: true);
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (q) => _load(() => widget.source.search(q), replace: q.trim().isEmpty),
            ),
          ),
          if (page != null)
            ListTile(
              dense: true,
              leading: _stack.length > 1
                  ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
                  : null,
              title: Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _body(page)),
        ],
      ),
    );
  }

  Widget _body(CatalogPage? page) {
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text: _error!,
        action: TextButton(
          onPressed: () => _load(
            _stack.isEmpty ? widget.source.root : () => widget.source.open(_stack.last.url!),
            replace: _stack.isEmpty,
          ),
          child: const Text('Retry'),
        ),
      );
    }
    if (page == null) return const SizedBox.shrink();
    if (page.entries.isEmpty) {
      return const _Message(icon: Icons.search_off, text: 'Nothing here.');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: ListView.separated(
        itemCount: page.entries.length + (page.nextPage != null ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
        itemBuilder: (context, i) {
          if (i == page.entries.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final entry = page.entries[i];
          return _EntryTile(
            entry: entry,
            onOpenFeed: entry.isNavigation ? () => _load(() => widget.source.open(entry.navigation!)) : null,
            onDownload: entry.isBook ? () => _download(entry) : null,
          );
        },
      ),
    );
  }

  void _download(CatalogEntry entry) {
    Services.of(context).downloads.enqueue(entry, widget.source);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading "${entry.title}"')),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.onOpenFeed, this.onDownload});

  final CatalogEntry entry;
  final VoidCallback? onOpenFeed;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = entry.thumbnail;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: SizedBox(
        width: 56,
        height: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: thumb == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(entry.isNavigation ? Icons.folder_outlined : Icons.menu_book_outlined),
                )
              : Image.network(
                  thumb.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.menu_book_outlined),
                  ),
                ),
        ),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.authorLine.isNotEmpty ? entry.authorLine : (entry.summary ?? ''),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onOpenFeed ?? () => _showDetail(context),
      trailing: onOpenFeed != null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_outlined),
              onPressed: onDownload,
            ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
            if (entry.authorLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.authorLine, style: Theme.of(context).textTheme.titleSmall),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onDownload?.call();
              },
              icon: const Icon(Icons.download),
              label: const Text('Download to library'),
            ),
            if (entry.summary != null) ...[
              const SizedBox(height: 16),
              Text(entry.summary!),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const _Message(
        icon: Icons.link_off,
        text: 'No primary source configured.\nSet an OPDS base URL in Settings.',
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
