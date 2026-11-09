import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:folio_core/folio_core.dart';

import '../services/app_services.dart';

Future<void> openReader(BuildContext context, Book book) async {
  final library = Services.of(context).library;
  final messenger = ScaffoldMessenger.of(context);
  final File file;
  try {
    file = await library.prepareForReading(book);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open "${book.title}": $e')));
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ReaderScreen(book: book, file: file)),
  );
  await library.reload();
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, required this.file});

  final Book book;
  final File file;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = ReaderController();
  bool _chrome = true;
  late ReaderStyle _style;
  Timer? _saveTimer;
  ReaderLocation? _pending;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _style = Services.of(context).settings.readerStyle;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flushProgress();
    if (widget.book.kind == BookKind.folder) {
      Services.of(context).library.clearReaderCache();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  void _onRelocate(ReaderLocation loc) {
    _pending = loc;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushProgress);
  }

  void _flushProgress() {
    final loc = _pending;
    if (loc == null) return;
    _pending = null;
    Services.of(context).library.saveProgress(widget.book.id, cfi: loc.cfi, progress: loc.fraction);
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(_chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  Color get _pageColor => switch (_style.theme) {
        ReaderTheme.light => const Color(0xFFFFFFFF),
        ReaderTheme.sepia => const Color(0xFFF4ECD8),
        ReaderTheme.dark => const Color(0xFF121212),
      };

  @override
  Widget build(BuildContext context) {
    final library = Services.of(context).library;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: _chrome
          ? AppBar(
              title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(tooltip: 'Contents', icon: const Icon(Icons.toc), onPressed: _showToc),
                IconButton(
                  tooltip: 'Bookmarks',
                  icon: const Icon(Icons.bookmarks_outlined),
                  onPressed: _showBookmarks,
                ),
                IconButton(
                  tooltip: 'Text and theme',
                  icon: const Icon(Icons.text_fields),
                  onPressed: _showStyle,
                ),
              ],
            )
          : null,
      body: SafeArea(
        top: !_chrome,
        child: Stack(
          children: [
            Positioned.fill(
              child: FolioReaderView(
                bookFile: widget.file,
                rootDir: library.rootDir,
                controller: _controller,
                initialCfi: widget.book.lastCfi,
                style: _style,
                onRelocate: _onRelocate,
                onToggleChrome: _toggleChrome,
              ),
            ),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.error != null) {
                  return _ReaderError(message: _controller.error!);
                }
                if (!_controller.ready) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: _chrome ? _ProgressBar(controller: _controller) : null,
    );
  }

  void _showToc() {
    final toc = _controller.toc;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => toc.isEmpty
            ? const Center(child: Text('This book has no table of contents.'))
            : ListView.builder(
                controller: scroll,
                itemCount: toc.length,
                itemBuilder: (context, i) => ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0 + toc[i].depth * 16, right: 16),
                  title: Text(toc[i].label),
                  selected: toc[i].label == _controller.location?.chapter,
                  onTap: () {
                    Navigator.pop(context);
                    _controller.goTo(toc[i].href);
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _showBookmarks() async {
    final library = Services.of(context).library;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BookmarksSheet(
        library: library,
        book: widget.book,
        controller: _controller,
      ),
    );
  }

  void _showStyle() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(ReaderStyle s) {
            setState(() => _style = s);
            setSheet(() {});
            _controller.setStyle(s);
            Services.of(context).settings.setReaderStyle(s);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ReaderTheme>(
                  segments: const [
                    ButtonSegment(value: ReaderTheme.light, label: Text('Light')),
                    ButtonSegment(value: ReaderTheme.sepia, label: Text('Sepia')),
                    ButtonSegment(value: ReaderTheme.dark, label: Text('Dark')),
                  ],
                  selected: {_style.theme},
                  onSelectionChanged: (s) => update(_style.copyWith(theme: s.first)),
                ),
                const SizedBox(height: 20),
                Text('Text size ${_style.fontSize}%', style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.text_decrease),
                      onPressed: _style.fontSize <= 70
                          ? null
                          : () => update(_style.copyWith(fontSize: _style.fontSize - 10)),
                    ),
                    Expanded(
                      child: Slider(
                        min: 70,
                        max: 200,
                        divisions: 13,
                        value: _style.fontSize.toDouble(),
                        onChanged: (v) => update(_style.copyWith(fontSize: v.round())),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_increase),
                      onPressed: _style.fontSize >= 200
                          ? null
                          : () => update(_style.copyWith(fontSize: _style.fontSize + 10)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.controller});

  final ReaderController controller;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final loc = controller.location;
        final fraction = _dragging ?? loc?.fraction ?? 0;
        return BottomAppBar(
          height: 72,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: controller.prev),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      loc?.chapter ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      value: fraction.clamp(0.0, 1.0),
                      onChanged: controller.ready ? (v) => setState(() => _dragging = v) : null,
                      onChangeEnd: (v) {
                        setState(() => _dragging = null);
                        controller.goToFraction(v);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${(fraction * 100).round()}%', textAlign: TextAlign.center),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: controller.next),
            ],
          ),
        );
      },
    );
  }
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({required this.library, required this.book, required this.controller});

  final LibraryService library;
  final Book book;
  final ReaderController controller;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  List<Bookmark> _marks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final marks = await widget.library.bookmarks(widget.book.id);
    if (mounted) setState(() => _marks = marks);
  }

  Future<void> _add() async {
    final loc = widget.controller.location;
    if (loc == null) return;
    final pct = (loc.fraction * 100).round();
    final label = loc.chapter == null || loc.chapter!.isEmpty ? '$pct%' : '${loc.chapter} · $pct%';
    await widget.library.addBookmark(widget.book.id, loc.cfi, label, loc.fraction);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: const Text('Bookmark this page'),
            enabled: widget.controller.location != null,
            onTap: _add,
          ),
          const Divider(height: 1),
          if (_marks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No bookmarks yet.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _marks.length,
                itemBuilder: (context, i) {
                  final m = _marks[i];
                  return ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(m.label),
                    onTap: () {
                      Navigator.pop(context);
                      widget.controller.goTo(m.cfi);
                    },
                    trailing: IconButton(
                      tooltip: 'Delete bookmark',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.library.deleteBookmark(m.id);
                        await _load();
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('This book could not be opened.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
