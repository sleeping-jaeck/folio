import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio_core/folio_core.dart';

File _writeEpub(Directory dir, {bool withCover = true}) {
  final archive = Archive()
    ..add(ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip')))
    ..add(ArchiveFile.bytes(
      'META-INF/container.xml',
      utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
    ))
    ..add(ArchiveFile.bytes(
      'OEBPS/content.opf',
      utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:folio:test</dc:identifier>
    <dc:title>A Folio Test Book</dc:title>
    <dc:creator>Test Writer</dc:creator>
    <dc:creator>Second Writer</dc:creator>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    ${withCover ? '<item id="cov" href="images/cover.png" media-type="image/png" properties="cover-image"/>' : ''}
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>'''),
    ))
    ..add(ArchiveFile.bytes('OEBPS/ch1.xhtml', utf8.encode('<html><body><p>Hello.</p></body></html>')));
  if (withCover) {
    archive.add(ArchiveFile.bytes('OEBPS/images/cover.png', Uint8List.fromList([1, 2, 3, 4])));
  }
  final file = File('${dir.path}/test_book.epub');
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('folio_meta'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads title, creators and EPUB3 cover-image', () async {
    final meta = await readEpubMetadata(_writeEpub(dir));
    expect(meta.title, 'A Folio Test Book');
    expect(meta.authors, ['Test Writer', 'Second Writer']);
    expect(meta.cover, [1, 2, 3, 4]);
    expect(meta.coverExtension, '.png');
  });

  test('works without a cover', () async {
    final meta = await readEpubMetadata(_writeEpub(dir, withCover: false));
    expect(meta.title, 'A Folio Test Book');
    expect(meta.cover, isNull);
  });

  test('falls back to the file name for non-EPUB files', () async {
    final f = File('${dir.path}/my_notes_file.epub')..writeAsStringSync('not a zip');
    final meta = await readEpubMetadata(f);
    expect(meta.title, 'my notes file');
    expect(meta.authors, isEmpty);
  });
}
