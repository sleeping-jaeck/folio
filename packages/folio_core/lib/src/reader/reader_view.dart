import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'reader_controller.dart';

const _assetHost = 'appassets.androidplatform.net';
const _readerPage =
    'https://$_assetHost/assets/flutter_assets/packages/folio_core/assets/reader/reader.html';

/// Offline EPUB reader. The book file must live under [rootDir] (the app
/// support directory), which is served to the WebView at `/files/`.
class FolioReaderView extends StatefulWidget {
  const FolioReaderView({
    super.key,
    required this.bookFile,
    required this.rootDir,
    required this.controller,
    this.initialCfi,
    this.style = const ReaderStyle(),
    this.onRelocate,
    this.onToggleChrome,
  });

  final File bookFile;
  final Directory rootDir;
  final ReaderController controller;
  final String? initialCfi;
  final ReaderStyle style;
  final ValueChanged<ReaderLocation>? onRelocate;
  final VoidCallback? onToggleChrome;

  @override
  State<FolioReaderView> createState() => _FolioReaderViewState();
}

class _FolioReaderViewState extends State<FolioReaderView> {
  bool _opened = false;

  String get _bookUrl {
    final rel = p.relative(widget.bookFile.path, from: widget.rootDir.path);
    final segments = p.split(rel).map(Uri.encodeComponent).join('/');
    return 'https://$_assetHost/files/$segments';
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_readerPage)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
        disableContextMenu: false,
        allowFileAccess: false,
        allowContentAccess: false,
        cacheEnabled: false,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        overScrollMode: OverScrollMode.NEVER,
        webViewAssetLoader: WebViewAssetLoader(
          domain: _assetHost,
          pathHandlers: [
            AssetsPathHandler(path: '/assets/'),
            InternalStoragePathHandler(path: '/files/', directory: widget.rootDir.path),
          ],
        ),
      ),
      onWebViewCreated: (web) {
        widget.controller.attach(web);
        web.addJavaScriptHandler(handlerName: 'jsReady', callback: (_) => _open(web));
        web.addJavaScriptHandler(
          handlerName: 'ready',
          callback: (args) {
            final data = (args.isNotEmpty ? args.first : null) as Map? ?? const {};
            final toc = ((data['toc'] as List?) ?? const [])
                .whereType<Map>()
                .map((t) => TocItem(
                      label: '${t['label'] ?? ''}',
                      href: '${t['href'] ?? ''}',
                      depth: (t['depth'] as num?)?.toInt() ?? 0,
                    ))
                .where((t) => t.label.isNotEmpty && t.href.isNotEmpty)
                .toList();
            widget.controller.handleReady(toc);
          },
        );
        web.addJavaScriptHandler(
          handlerName: 'relocate',
          callback: (args) {
            final data = (args.isNotEmpty ? args.first : null) as Map? ?? const {};
            final cfi = data['cfi'] as String?;
            if (cfi == null) return;
            final loc = ReaderLocation(
              cfi: cfi,
              fraction: (data['fraction'] as num?)?.toDouble() ?? 0,
              chapter: data['chapter'] as String?,
            );
            widget.controller.handleRelocate(loc);
            widget.onRelocate?.call(loc);
          },
        );
        web.addJavaScriptHandler(
          handlerName: 'toggleChrome',
          callback: (_) => widget.onToggleChrome?.call(),
        );
        web.addJavaScriptHandler(
          handlerName: 'error',
          callback: (args) => widget.controller
              .handleError(args.isNotEmpty ? '${args.first}' : 'Unknown error'),
        );
      },
      shouldOverrideUrlLoading: (_, action) async {
        final url = action.request.url;
        if (url == null || url.host == _assetHost || url.scheme == 'blob' || url.scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
      onConsoleMessage: (_, message) => debugPrint('Folio reader: ${message.message}'),
    );
  }

  Future<void> _open(InAppWebViewController web) async {
    if (_opened) return;
    _opened = true;
    final args = [
      jsonEncode(_bookUrl),
      jsonEncode(widget.initialCfi),
      jsonEncode(widget.style.toJson()),
    ].join(', ');
    await web.evaluateJavascript(source: 'folio.open($args)');
  }
}
