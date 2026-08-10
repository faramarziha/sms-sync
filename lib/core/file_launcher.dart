import 'dart:io';
import 'package:flutter/foundation.dart';
import '../platform/android_native_bridge.dart';

class FileLauncher {
  static Future<void> openFile(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isAndroid) {
        await AndroidNativeBridge().openFile(path);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      debugPrint('Error launching file: $e');
    }
  }
}
