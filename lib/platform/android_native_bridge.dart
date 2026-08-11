import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.faramarzi.smssync/native_channel');

  static final _onSmsReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onSmsReceivedStream => _onSmsReceivedController.stream;

  AndroidNativeBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        try {
          final data = Map<String, dynamic>.from(call.arguments);
          _onSmsReceivedController.add(data);
        } catch (e) {
          debugPrint("Error processing incoming SMS method call: $e");
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSubscriptionInfo() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getSubscriptionInfo');
      return result?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    } on PlatformException catch (e) {
      debugPrint("Failed to get subscription info: '${e.message}'.");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRecentSms({int limit = 50}) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getRecentSms', {'limit': limit});
      return result?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    } on PlatformException catch (e) {
      debugPrint("Failed to get recent SMS: '${e.message}'.");
      return [];
    }
  }

  Future<bool> openFile(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('openFile', {'path': path});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to open file: '${e.message}'.");
      return false;
    }
  }

  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } on PlatformException catch (e) {
      debugPrint("Failed to start foreground service: '${e.message}'.");
    }
  }

  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop foreground service: '${e.message}'.");
    }
  }
}
