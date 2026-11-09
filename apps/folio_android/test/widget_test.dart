import 'package:flutter_test/flutter_test.dart';
import 'package:folio_catalog/folio_catalog.dart';

void main() {
  test('Browse tabs put the primary slot first, then the built-in sources', () {
    final names = buildSources(primaryBaseUrl: placeholderPrimaryUrl).map((s) => s.name);
    expect(names, ['Primary', 'Gutenberg', 'Standard Ebooks', 'Open Library']);
  });

  test('A real primary URL makes the primary slot configured', () {
    final primary = buildSources(primaryBaseUrl: 'https://books.example.org/opds').first;
    expect(primary.isConfigured, isTrue);
  });
}
