import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_services.dart';
import 'browse_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<String>? _incoming;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = Services.of(context);
    _incoming = services.folders.incomingDocuments.listen(_importIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await services.folders.takeIncomingDocument();
      if (pending != null) await _importIncoming(pending);
      await services.library.rescan();
    });
  }

  @override
  void dispose() {
    _incoming?.cancel();
    super.dispose();
  }

  Future<void> _importIncoming(String uri) async {
    final services = Services.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final book = await services.library.importDocument(uri);
      if (!mounted) return;
      setState(() => _index = 0);
      await openReader(context, book);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = Services.of(context).downloads;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          LibraryScreen(),
          BrowseScreen(),
          DownloadsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) => NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark),
              label: 'Library',
            ),
            const NavigationDestination(
              icon: Icon(Icons.travel_explore_outlined),
              selectedIcon: Icon(Icons.travel_explore),
              label: 'Browse',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: downloads.activeCount > 0,
                label: Text('${downloads.activeCount}'),
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: const Icon(Icons.download),
              label: 'Downloads',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
