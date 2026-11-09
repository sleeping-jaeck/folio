import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

enum ReaderTheme { light, sepia, dark }

class ReaderStyle {
  const ReaderStyle({
    this.theme = ReaderTheme.light,
    this.fontSize = 100,
    this.lineHeight = 1.5,
  });

  final ReaderTheme theme;

  /// Percentage of the publisher's base size.
  final int fontSize;
  final double lineHeight;

  ReaderStyle copyWith({ReaderTheme? theme, int? fontSize, double? lineHeight}) =>
      ReaderStyle(
        theme: theme ?? this.theme,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
      );

  Map<String, Object> toJson() =>
      {'theme': theme.name, 'fontSize': fontSize, 'lineHeight': lineHeight};
}

class ReaderLocation {
  const ReaderLocation({required this.cfi, required this.fraction, this.chapter});
  final String cfi;
  final double fraction;
  final String? chapter;
}

class TocItem {
  const TocItem({required this.label, required this.href, required this.depth});
  final String label;
  final String href;
  final int depth;
}

/// Drives the reader WebView from Flutter.
class ReaderController extends ChangeNotifier {
  InAppWebViewController? _web;

  ReaderLocation? _location;
  List<TocItem> _toc = const [];
  bool _ready = false;
  String? _error;

  ReaderLocation? get location => _location;
  List<TocItem> get toc => _toc;
  bool get ready => _ready;
  String? get error => _error;

  void attach(InAppWebViewController web) => _web = web;

  void detach() => _web = null;

  void next() => _call('folio.next()');
  void prev() => _call('folio.prev()');
  void goTo(String target) => _call('folio.goTo(${jsonEncode(target)})');
  void goToFraction(double fraction) =>
      _call('folio.goToFraction(${fraction.clamp(0.0, 1.0)})');
  void setStyle(ReaderStyle style) =>
      _call('folio.setStyle(${jsonEncode(style.toJson())})');

  void handleReady(List<TocItem> toc) {
    _toc = toc;
    _ready = true;
    notifyListeners();
  }

  void handleRelocate(ReaderLocation location) {
    _location = location;
    notifyListeners();
  }

  void handleError(String message) {
    _error = message;
    notifyListeners();
  }

  Future<void> _call(String source) async {
    await _web?.evaluateJavascript(source: source);
  }
}
