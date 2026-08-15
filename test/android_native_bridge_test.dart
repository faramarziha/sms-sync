import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_sync/platform/android_native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.faramarzi.smssync/native_channel');
  late AndroidNativeBridge bridge;

  setUp(() {
    bridge = AndroidNativeBridge();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('getSubscriptionInfo', () {
    test('returns empty list on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getSubscriptionInfo') {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Permission denied',
          );
        }
        return null;
      });

      final result = await bridge.getSubscriptionInfo();
      expect(result, isEmpty);
      expect(result, isA<List<Map<String, dynamic>>>());
    });

    test('returns subscription data on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getSubscriptionInfo') {
          return [
            {
              'subscription_id': 1,
              'phone_number': '+1234567890',
              'carrier_name': 'Test Carrier',
              'sim_slot': 0,
            },
          ];
        }
        return null;
      });

      final result = await bridge.getSubscriptionInfo();
      expect(result.length, 1);
      expect(result[0]['phone_number'], '+1234567890');
      expect(result[0]['carrier_name'], 'Test Carrier');
    });

    test('returns empty list when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getSubscriptionInfo') {
          return null;
        }
        return null;
      });

      final result = await bridge.getSubscriptionInfo();
      expect(result, isEmpty);
    });
  });

  group('getRecentSms', () {
    test('returns empty list on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getRecentSms') {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'SMS permission denied',
          );
        }
        return null;
      });

      final result = await bridge.getRecentSms(limit: 10);
      expect(result, isEmpty);
    });

    test('returns SMS data on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getRecentSms') {
          expect(call.arguments['limit'], 25);
          return [
            {
              'id': 1,
              'address': '+1234567890',
              'body': 'Hello world',
              'date': 1700000000000,
              'type': 1,
            },
          ];
        }
        return null;
      });

      final result = await bridge.getRecentSms(limit: 25);
      expect(result.length, 1);
      expect(result[0]['body'], 'Hello world');
    });

    test('passes default limit of 50', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getRecentSms') {
          expect(call.arguments['limit'], 50);
          return [];
        }
        return null;
      });

      await bridge.getRecentSms();
    });
  });

  group('openFile', () {
    test('returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'openFile') {
          throw PlatformException(
            code: 'FILE_NOT_FOUND',
            message: 'File not found',
          );
        }
        return null;
      });

      final result = await bridge.openFile('/some/path/file.txt');
      expect(result, isFalse);
    });

    test('returns true on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'openFile') {
          expect(call.arguments['path'], '/test/file.pdf');
          return true;
        }
        return null;
      });

      final result = await bridge.openFile('/test/file.pdf');
      expect(result, isTrue);
    });

    test('returns false when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'openFile') {
          return null;
        }
        return null;
      });

      final result = await bridge.openFile('/test/file.pdf');
      expect(result, isFalse);
    });
  });

  group('startForegroundService', () {
    test('does not throw on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'startForegroundService') {
          throw PlatformException(
            code: 'SERVICE_ERROR',
            message: 'Failed to start service',
          );
        }
        return null;
      });

      // Should not throw — error is caught internally
      await expectLater(bridge.startForegroundService(), completes);
    });

    test('completes successfully on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'startForegroundService') {
          return true;
        }
        return null;
      });

      await expectLater(bridge.startForegroundService(), completes);
    });
  });

  group('isIgnoringBatteryOptimizations', () {
    test('returns true when battery optimization is ignored', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return true;
        }
        return null;
      });

      final result = await bridge.isIgnoringBatteryOptimizations();
      expect(result, isTrue);
    });

    test('returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'isIgnoringBatteryOptimizations') {
          throw PlatformException(code: 'ERROR', message: 'Failed');
        }
        return null;
      });

      final result = await bridge.isIgnoringBatteryOptimizations();
      expect(result, isFalse);
    });
  });

  group('requestIgnoreBatteryOptimizations', () {
    test('returns true on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'requestIgnoreBatteryOptimizations') {
          return true;
        }
        return null;
      });

      final result = await bridge.requestIgnoreBatteryOptimizations();
      expect(result, isTrue);
    });

    test('returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'requestIgnoreBatteryOptimizations') {
          throw PlatformException(code: 'ERROR', message: 'Failed');
        }
        return null;
      });

      final result = await bridge.requestIgnoreBatteryOptimizations();
      expect(result, isFalse);
    });
  });
}
