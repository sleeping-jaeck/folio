import 'package:flutter/material.dart';
import 'package:folio_catalog/folio_catalog.dart';
import 'package:folio_core/folio_core.dart';

import '../services/app_services.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Library folders'),
          ListenableBuilder(
            listenable: services.library,
            builder: (context, _) => Column(
              children: [
                for (final folder in services.library.folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    subtitle: Text(
                      '${services.library.books.where((b) => b.folderUri == folder.uri).length} books',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove folder',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeFolder(context, folder),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('Add library folder'),
                  subtitle: const Text('EPUBs inside are read in place, nothing is copied'),
                  onTap: () => _addFolder(context),
                ),
                ListTile(
                  leading: services.library.scanning
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  title: const Text('Rescan folders'),
                  enabled: !services.library.scanning && services.library.folders.isNotEmpty,
                  onTap: services.library.rescan,
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Primary source'),
          ListenableBuilder(
            listenable: services.settings,
            builder: (context, _) {
              final url = services.settings.primaryBaseUrl;
              final configured = url != placeholderPrimaryUrl;
              return ListTile(
                leading: const Icon(Icons.link),
                title: const Text('OPDS base URL'),
                subtitle: Text(configured ? url : 'Not configured ($url)'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editPrimary(context, url),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'The Primary tab in Browse reads any standard OPDS catalog, such as your own '
              'Calibre-Web or Kavita server. Gutenberg, Standard Ebooks and Open Library are built in.',
            ),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Folio',
            applicationVersion: '0.1.0',
            applicationLegalese: 'Open source (MIT). EPUB rendering by foliate-js (MIT).',
          ),
        ],
      ),
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final folder = await Services.of(context).library.addFolder();
      if (folder != null) {
        messenger.showSnackBar(SnackBar(content: Text('Added "${folder.name}"')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add folder: $e')));
    }
  }

  Future<void> _removeFolder(BuildContext context, LibraryFolder folder) async {
    final library = Services.of(context).library;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "${folder.name}"?'),
        content: const Text('Its books leave your library. The files on your phone are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await library.removeFolder(folder);
  }

  Future<void> _editPrimary(BuildContext context, String current) async {
    final settings = Services.of(context).settings;
    final controller = TextEditingController(text: current == placeholderPrimaryUrl ? '' : current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Primary source'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'OPDS base URL',
            hintText: placeholderPrimaryUrl,
            helperText: 'Leave empty to reset to the placeholder',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final uri = Uri.tryParse(result.trim());
    if (result.trim().isNotEmpty && (uri == null || !uri.hasScheme || uri.host.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a full URL starting with https://')),
        );
      }
      return;
    }
    await settings.setPrimaryBaseUrl(result);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
