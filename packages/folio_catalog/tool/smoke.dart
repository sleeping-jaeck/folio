// Live check against the built-in sources: dart run tool/smoke.dart
import 'package:folio_catalog/folio_catalog.dart';

Future<void> main() async {
  final sources = buildSources(primaryBaseUrl: placeholderPrimaryUrl);
  for (final s in sources.where((s) => s.isConfigured)) {
    try {
      final root = await s.root();
      final results = await s.search(s.id == 'standardebooks' ? '' : 'sherlock');
      final book = results.entries.firstWhere(
          (e) =>
              e.acquisitions.isNotEmpty ||
              e.extra.isNotEmpty ||
              RegExp(r'/ebooks/\d+').hasMatch('${e.navigation}'),
          orElse: () => root.entries.first);
      final url = await s.resolveDownloadUrl(book);
      print('${s.name}: root=${root.entries.length} '
          'search=${results.entries.length} first="${book.title}" epub=$url');
    } on Exception catch (e) {
      print('${s.name}: FAILED $e');
    }
  }
}
