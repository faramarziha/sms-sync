import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_sync/core/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = SystemChannels.platform;
  late ClipboardService service;
  String mockClipboard = '';

  setUp(() {
    service = ClipboardService();
    service.reset();
    mockClipboard = '';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': mockClipboard};
      }
      if (call.method == 'Clipboard.setData') {
        mockClipboard = (call.arguments as Map)['text'] as String? ?? '';
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ClipboardService — Normalization & Basics', () {
    test('normalize converts CRLF and CR to LF', () {
      expect(ClipboardService.normalize('hello\r\nworld'), 'hello\nworld');
      expect(ClipboardService.normalize('hello\rworld'), 'hello\nworld');
      expect(ClipboardService.normalize('hello\nworld'), 'hello\nworld');
    });

    test('getText returns null or string safely', () async {
      mockClipboard = 'Test clipboard';
      final text = await service.getText();
      expect(text, 'Test clipboard');
    });

    test('setText ignores empty strings', () async {
      await service.setText('');
      expect(mockClipboard, '');
      expect(service.lastContent, '');
    });

    test('setText updates clipboard and lastContent', () async {
      await service.setText('Hello world');
      expect(mockClipboard, 'Hello world');
      expect(service.lastContent, 'Hello world');
    });

    test('setText normalizes line endings before checking deduplication', () async {
      await service.setText('Line 1\r\nLine 2');
      expect(mockClipboard, 'Line 1\r\nLine 2');
      expect(service.lastContent, 'Line 1\nLine 2');

      // Second call with same normalized content should be ignored (no redundant write)
      mockClipboard = 'Tampered';
      await service.setText('Line 1\nLine 2');
      expect(mockClipboard, 'Tampered'); // Not overwritten because normalized match was detected
    });
  });

  group('ClipboardService — Monitoring & Echo Prevention', () {
    test('startMonitoring detects new clipboard content', () async {
      String? received;
      service.startMonitoring((newText) {
        received = newText;
      });

      mockClipboard = 'User copied this';

      // Allow timer to trigger
      await Future.delayed(const Duration(milliseconds: 1500));
      expect(received, 'User copied this');
      expect(service.lastContent, 'User copied this');
    });

    test('startMonitoring suppresses echo when text was set via setText', () async {
      final List<String> receivedEvents = [];
      service.startMonitoring((newText) {
        receivedEvents.add(newText);
      });

      // Simulate remote network setting clipboard
      await service.setText('Remote Synced Text\r\nSecond Line');

      // On Windows, OS clipboard will return the text with \r\n
      mockClipboard = 'Remote Synced Text\r\nSecond Line';

      // Wait for timer ticks
      await Future.delayed(const Duration(milliseconds: 2600));

      // Should NOT fire onChanged because this text was set by setText (echo loop prevention)
      expect(receivedEvents, isEmpty);
    });

    test('startMonitoring rejects payloads exceeding 500 KB limit', () async {
      String? received;
      service.startMonitoring((newText) {
        received = newText;
      });

      // 600 KB oversized text
      mockClipboard = 'A' * (600 * 1024);

      await Future.delayed(const Duration(milliseconds: 1500));
      expect(received, isNull);
    });

    test('stopMonitoring stops periodic timer', () async {
      String? received;
      service.startMonitoring((newText) {
        received = newText;
      });

      service.stopMonitoring();
      mockClipboard = 'New text after stop';

      await Future.delayed(const Duration(milliseconds: 1500));
      expect(received, isNull);
    });
  });

  group('ClipboardService — Error Handling', () {
    test('handles PlatformException during getData gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'Clipboard.getData') {
          throw PlatformException(code: 'LOCKED', message: 'Clipboard locked');
        }
        return null;
      });

      final result = await service.getText();
      expect(result, isNull);
    });

    test('handles PlatformException during setData gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'LOCKED', message: 'Clipboard locked');
        }
        return null;
      });

      // Should not throw
      await expectLater(service.setText('Test'), completes);
    });
  });
}
