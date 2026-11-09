import 'package:flutter/widgets.dart';
import 'package:folio_catalog/folio_catalog.dart';
import 'package:folio_core/folio_core.dart';

import '../platform/saf_folder_access.dart';
import 'download_queue.dart';
import 'settings.dart';

/// Everything the screens share, created once at startup.
class AppServices {
  AppServices._(this.folders, this.library, this.settings, this.downloads) {
    _rebuildSources();
    settings.addListener(_onSettings);
  }

  final SafFolderAccess folders;
  final LibraryService library;
  final Settings settings;
  final DownloadQueue downloads;

  /// Browse tabs. Rebuilt when the primary base URL changes.
  final ValueNotifier<List<CatalogSource>> sources = ValueNotifier(const []);
  String? _builtFor;

  static Future<AppServices> start() async {
    final folders = SafFolderAccess();
    final settings = await Settings.load();
    final library = await LibraryService.open(folders);
    return AppServices._(folders, library, settings, DownloadQueue(library));
  }

  void _onSettings() {
    if (settings.primaryBaseUrl != _builtFor) _rebuildSources();
  }

  void _rebuildSources() {
    _builtFor = settings.primaryBaseUrl;
    sources.value = buildSources(primaryBaseUrl: settings.primaryBaseUrl);
  }
}

/// Exposes [AppServices] to the widget tree.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}
