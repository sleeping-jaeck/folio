import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class EpubMetadata {
  const EpubMetadata({
    required this.title,
    required this.authors,
    this.cover,
    this.coverExtension,
  });

  final String title;
  final List<String> authors;
  final Uint8List? cover;
  final String? coverExtension;
}

/// Reads title, authors and cover from an EPUB file. Falls back to the file
/// name when the package metadata is missing or unreadable.
Future<EpubMetadata> readEpubMetadata(File file, {String? fallbackName}) async {
  final fallback = _titleFromName(fallbackName ?? p.basename(file.path));
  InputFileStream? input;
  try {
    input = InputFileStream(file.path);
    final archive = ZipDecoder().decodeStream(input);
    return _parse(archive, fallback);
  } catch (_) {
    return EpubMetadata(title: fallback, authors: const []);
  } finally {
    await input?.close();
  }
}

EpubMetadata _parse(Archive archive, String fallbackTitle) {
  final container = archive.find('META-INF/container.xml');
  if (container == null) {
    return EpubMetadata(title: fallbackTitle, authors: const []);
  }
  final containerDoc = XmlDocument.parse(_utf8(container.content));
  final rootfile = containerDoc
      .findAllElements('rootfile', namespace: '*')
      .map((e) => e.getAttribute('full-path'))
      .whereType<String>()
      .firstOrNull;
  if (rootfile == null) {
    return EpubMetadata(title: fallbackTitle, authors: const []);
  }
  final opfFile = archive.find(rootfile);
  if (opfFile == null) {
    return EpubMetadata(title: fallbackTitle, authors: const []);
  }
  final opf = XmlDocument.parse(_utf8(opfFile.content));
  final opfDir = p.posix.dirname(rootfile);

  final title = opf
          .findAllElements('title', namespace: '*')
          .map((e) => e.innerText.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  final authors = opf
      .findAllElements('creator', namespace: '*')
      .map((e) => e.innerText.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  final coverHref = _coverHref(opf);
  Uint8List? cover;
  String? ext;
  if (coverHref != null) {
    final path = p.posix.normalize(
        opfDir == '.' ? coverHref : p.posix.join(opfDir, coverHref));
    final entry = archive.find(Uri.decodeFull(path)) ?? archive.find(path);
    if (entry != null) {
      cover = entry.content;
      ext = p.extension(path).toLowerCase();
    }
  }

  return EpubMetadata(
    title: title.isEmpty ? fallbackTitle : title,
    authors: authors,
    cover: cover,
    coverExtension: ext,
  );
}

String? _coverHref(XmlDocument opf) {
  final items = opf.findAllElements('item', namespace: '*').toList();
  for (final item in items) {
    final props = item.getAttribute('properties') ?? '';
    if (props.split(' ').contains('cover-image')) return item.getAttribute('href');
  }
  final coverId = opf
      .findAllElements('meta', namespace: '*')
      .where((m) => m.getAttribute('name') == 'cover')
      .map((m) => m.getAttribute('content'))
      .whereType<String>()
      .firstOrNull;
  if (coverId != null) {
    for (final item in items) {
      if (item.getAttribute('id') == coverId) return item.getAttribute('href');
    }
  }
  for (final item in items) {
    final id = (item.getAttribute('id') ?? '').toLowerCase();
    final type = item.getAttribute('media-type') ?? '';
    if (id.contains('cover') && type.startsWith('image/')) {
      return item.getAttribute('href');
    }
  }
  return null;
}

String _utf8(Uint8List bytes) {
  final hasBom =
      bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
  return utf8.decode(hasBom ? bytes.sublist(3) : bytes, allowMalformed: true);
}

String _titleFromName(String name) {
  final base = p.basenameWithoutExtension(name).replaceAll('_', ' ').trim();
  return base.isEmpty ? 'Untitled' : base;
}
