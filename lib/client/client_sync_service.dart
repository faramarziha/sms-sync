import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../core/models/sync_message.dart';
import '../core/file_transfer_service.dart';
import '../transport/sync_transport.dart';
import '../transport/nsd_service.dart';
import '../platform/android_native_bridge.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/clipboard_service.dart';
import '../core/utils/otp_extractor.dart';

enum ClientState { idle, browsing, connecting, pairing, syncing, synced, error }

class ClientSyncService {
  final SyncTransport transport;
  final DiscoveryService discovery;
  final AndroidNativeBridge nativeBridge = AndroidNativeBridge();
  final FileTransferService fileTransfer = FileTransferService();
  final ClipboardService clipboardService = ClipboardService();

  /// Stable device ID derived from platform hash — survives app restarts
  late final String deviceId;
  late final String deviceName;

  ClientState _state = ClientState.idle;
  ClientState get state => _state;

  SyncScope _scope = SyncScope.both;
  SyncScope get scope => _scope;

  static const String _scopePrefKey = 'sync_scope';

  /// Load previously saved scope from persistent storage
  Future<void> loadSavedScope() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedScope = prefs.getString(_scopePrefKey);
      if (savedScope != null) {
        try {
          _scope = SyncScope.values.byName(savedScope);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Failed to load saved scope: $e');
    }
  }

  Timer? _periodicSyncTimer;

  final _stateController = StreamController<ClientState>.broadcast();
  Stream<ClientState> get stateStream => _stateController.stream;

  final _textMessagesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get textMessagesStream => _textMessagesController.stream;

  ClientSyncService(this.transport, this.discovery) {
    // Generate stable device ID from platform info
    final platformInfo = '${Platform.operatingSystem}_${Platform.operatingSystemVersion}_${Platform.localHostname}';
    deviceId = sha256.convert(utf8.encode(platformInfo)).toString().substring(0, 12);
    deviceName = Platform.isAndroid
        ? 'Android Phone (${Platform.operatingSystem})'
        : 'Mobile Client (${Platform.operatingSystem})';

    transport.messages.listen((message) {
      _handleMessage(message).catchError((e) {
        debugPrint('Error handling client message: $e');
      });
    });

    transport.connectionStatus.listen((connected) {
      if (!connected && (_state == ClientState.synced || _state == ClientState.syncing || _state == ClientState.pairing)) {
        _stopPeriodicSync();
        clipboardService.stopMonitoring();
        _stopForegroundService();
        _updateState(ClientState.idle);
      }
    });

    // Listen to real-time incoming SMS events from Android BroadcastReceiver
    nativeBridge.onSmsReceivedStream.listen((sms) {
      _handleIncomingSms(sms);
    });
  }

  Future<void> _handleIncomingSms(Map<String, dynamic> sms) async {
    final body = sms['body'] as String? ?? '';
    final address = sms['address'] as String? ?? 'SMS';

    // Send single incoming SMS to server
    final smsPayload = Map<String, dynamic>.from(sms);
    smsPayload['device_id'] = deviceId;
    smsPayload['device_name'] = deviceName;
    try {
      await transport.send(SyncMessage(
        type: SyncMessageType.sms,
        payload: smsPayload,
      ));
    } catch (_) {}

    // Extract OTP from real-time incoming SMS
    final otp = OtpExtractor.extractOtp(body);
    if (otp != null) {
      debugPrint("Real-time OTP extracted: $otp from $address");
      try {
        await transport.send(SyncMessage(
          type: SyncMessageType.otpCode,
          payload: {
            'otp': otp,
            'sender': address,
            'device_id': deviceId,
            'device_name': deviceName,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ));
      } catch (e) {
        debugPrint("Failed to send OTP code message: $e");
      }
    }
  }

  void _updateState(ClientState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  Future<void> startDiscovery() async {
    _updateState(ClientState.browsing);
    try {
      await transport.startServer(8081);
    } catch (e) {
      debugPrint("Client socket server start notice: $e");
    }
    if (discovery is NsdDiscoveryService) {
      await (discovery as NsdDiscoveryService).startBrowsing(type: 'mysync');
      await (discovery as NsdDiscoveryService).startAdvertising(deviceName, 8081, type: 'mysync');
    } else {
      await discovery.startBrowsing();
    }
  }

  Future<void> connectToServer(DiscoveredServer server) async {
    _updateState(ClientState.connecting);
    try {
      await transport.connect(server.address, server.port);
      _updateState(ClientState.pairing);
    } catch (e) {
      debugPrint('Connection to server failed: $e');
      _updateState(ClientState.error);
    }
  }

  Future<void> sendPairRequest(String pin, {SyncScope scope = SyncScope.both}) async {
    _scope = scope;
    // Persist scope selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scopePrefKey, scope.name);
    } catch (e) {
      debugPrint('Failed to save scope preference: $e');
    }
    await transport.send(SyncMessage(
      type: SyncMessageType.pairVerify,
      payload: {
        'pin': pin,
        'scope': scope.name,
        'device_id': deviceId,
        'device_name': deviceName,
      },
    ));
  }

  Future<void> _handleMessage(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageType.pairVerify:
        if (message.payload['status'] == 'success') {
          _updateState(ClientState.syncing);
          _startForegroundService();
          await _runSync();
        }
        break;
      case SyncMessageType.rawText:
        _textMessagesController.add(message.payload);
        break;
      case SyncMessageType.fileHeader:
        await fileTransfer.handleFileHeader(message.payload);
        break;
      case SyncMessageType.fileChunk:
        await fileTransfer.handleFileChunk(message.payload);
        break;
      case SyncMessageType.clipboardSync:
        final text = message.payload['text'] as String?;
        if (text != null && text.isNotEmpty) {
          await clipboardService.setText(text);
        }
        break;
      default:
        break;
    }
  }

  void _startForegroundService() {
    if (Platform.isAndroid) {
      nativeBridge.startForegroundService();
    }
  }

  void _stopForegroundService() {
    if (Platform.isAndroid) {
      nativeBridge.stopForegroundService();
    }
  }

  Future<void> sendRawText(String text) async {
    if (text.trim().isEmpty) return;
    final payload = {
      'text': text,
      'sender': deviceName,
      'device_id': deviceId,
      'device_name': deviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await transport.send(SyncMessage(
      type: SyncMessageType.rawText,
      payload: payload,
    ));
    _textMessagesController.add(payload);
  }

  Future<void> sendFile(File file) async {
    await fileTransfer.sendFile(
      file: file,
      sender: deviceName,
      sendMessage: (msg) => transport.send(msg),
    );
  }

  Future<void> _runSync() async {
    try {
      if (_scope == SyncScope.smsSim || _scope == SyncScope.both) {
        if (await Permission.sms.request().isGranted &&
            await Permission.phone.request().isGranted) {
          // Also request notification permission on Android 13+
          if (Platform.isAndroid) {
            await Permission.notification.request();
          }

          final sims = await nativeBridge.getSubscriptionInfo();
          if (sims.isNotEmpty) {
            final simPayloads = sims.map((sim) {
              final simPayload = Map<String, dynamic>.from(sim);
              simPayload['device_id'] = deviceId;
              simPayload['device_name'] = deviceName;
              return simPayload;
            }).toList();
            await transport.send(SyncMessage(
              type: SyncMessageType.contactInfoBatch,
              payload: {
                'device_id': deviceId,
                'device_name': deviceName,
                'records': simPayloads,
              },
            ));
          }

          final smsList = await nativeBridge.getRecentSms(limit: 100);
          if (smsList.isNotEmpty) {
            final smsPayloads = smsList.map((sms) {
              final smsPayload = Map<String, dynamic>.from(sms);
              smsPayload['device_id'] = deviceId;
              smsPayload['device_name'] = deviceName;
              return smsPayload;
            }).toList();
            await transport.send(SyncMessage(
              type: SyncMessageType.smsBatch,
              payload: {
                'device_id': deviceId,
                'device_name': deviceName,
                'records': smsPayloads,
              },
            ));
          }
        }
      }

      _updateState(ClientState.synced);
      _startClipboardSync();
      _startPeriodicSync();
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }

  void _startPeriodicSync() {
    _stopPeriodicSync();
    if (_scope == SyncScope.textFiles) return;

    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_state == ClientState.synced) {
        _runSync();
      }
    });
  }

  void _stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  void _startClipboardSync() {
    clipboardService.startMonitoring((newText) {
      if (_state == ClientState.synced) {
        transport.send(SyncMessage(
          type: SyncMessageType.clipboardSync,
          payload: {
            'text': newText,
            'device_id': deviceId,
            'device_name': deviceName,
          },
        ));
      }
    });
  }

  Future<void> disconnect() async {
    _stopPeriodicSync();
    _stopForegroundService();
    clipboardService.stopMonitoring();
    await transport.disconnect();
    _updateState(ClientState.idle);
  }

  Future<void> dispose() async {
    _stopPeriodicSync();
    _stopForegroundService();
    clipboardService.dispose();
    fileTransfer.dispose();
    await discovery.stopBrowsing();
    await discovery.stopAdvertising();
    await transport.disconnect();
    _stateController.close();
    _textMessagesController.close();
  }
}
