import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  static final ClipboardService _instance = ClipboardService._internal();
  factory ClipboardService() => _instance;
  ClipboardService._internal();

  Timer? _clipboardTimer;
  String _lastContent = '';

  String get lastContent => _lastContent;

  /// Fetch current clipboard content as text.
  Future<String?> getText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  /// Copy text to system clipboard.
  Future<void> setText(String text) async {
    if (text.isEmpty || text == _lastContent) return;
    _lastContent = text;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  /// Start monitoring clipboard changes periodically.
  void startMonitoring(void Function(String newText) onChanged) {
    stopMonitoring();
    _clipboardTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final current = await getText();
        if (current != null && current.isNotEmpty && current != _lastContent) {
          _lastContent = current;
          onChanged(current);
        }
      } catch (_) {}
    });
  }

  /// Stop monitoring clipboard.
  void stopMonitoring() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
  }

  void dispose() {
    stopMonitoring();
  }
}
