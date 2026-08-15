import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ClipboardService {
  static final ClipboardService _instance = ClipboardService._internal();
  factory ClipboardService() => _instance;
  ClipboardService._internal();

  Timer? _clipboardTimer;
  String _lastContent = '';

  /// Maximum clipboard text size to automatically sync (500 KB) to avoid socket choking
  static const int maxAutoSyncSizeBytes = 500 * 1024;

  /// Cache of recently applied or sent clipboard contents to prevent echo loops
  final List<String> _recentHistory = [];
  static const int _maxHistoryEntries = 16;

  String get lastContent => _lastContent;

  /// Helper to normalize line endings across platforms (\r\n -> \n)
  static String normalize(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// Fetch current clipboard content as text.
  Future<String?> getText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (e) {
      debugPrint("Clipboard read error: $e");
      return null;
    }
  }

  /// Copy text to system clipboard with loop-suppression.
  Future<void> setText(String text) async {
    if (text.isEmpty) return;
    final normalized = normalize(text);
    if (normalized == _lastContent || _recentHistory.contains(normalized)) return;

    _lastContent = normalized;
    _addToHistory(normalized);

    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      debugPrint("Clipboard write error: $e");
    }
  }

  /// Start monitoring clipboard changes periodically.
  void startMonitoring(void Function(String newText) onChanged) {
    stopMonitoring();
    _clipboardTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      try {
        final current = await getText();
        if (current != null && current.isNotEmpty) {
          // Reject oversized text payloads
          if (current.length > maxAutoSyncSizeBytes) return;

          final normalized = normalize(current);
          if (normalized != _lastContent && !_recentHistory.contains(normalized)) {
            _lastContent = normalized;
            _addToHistory(normalized);
            onChanged(current);
          }
        }
      } catch (e) {
        debugPrint("Clipboard monitor error: $e");
      }
    });
  }

  void _addToHistory(String normalizedText) {
    if (_recentHistory.contains(normalizedText)) {
      _recentHistory.remove(normalizedText);
    }
    _recentHistory.add(normalizedText);
    if (_recentHistory.length > _maxHistoryEntries) {
      _recentHistory.removeAt(0);
    }
  }

  /// Stop monitoring clipboard.
  void stopMonitoring() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
  }

  void reset() {
    stopMonitoring();
    _lastContent = '';
    _recentHistory.clear();
  }

  void dispose() {
    reset();
  }
}
