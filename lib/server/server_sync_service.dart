import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models/sync_message.dart';
import '../core/file_transfer_service.dart';
import '../transport/sync_transport.dart';
import '../transport/websocket_transport.dart';
import '../transport/nsd_service.dart';
import '../core/pairing_service.dart';
import '../core/clipboard_service.dart';
import 'db/database_service.dart';
import 'services/backup_service.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ServerState { idle, advertising, connected, paired }

class ConnectedDeviceInfo {
  final String deviceId;
  final String deviceName;
  final SyncScope scope;

  ConnectedDeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.scope,
  });
}

class ServerSyncService {
  final SyncTransport transport;
  final DiscoveryService discovery;
  final PairingService pairing = PairingService();
  final DatabaseService db = DatabaseService();
  late final BackupService backupService = BackupService(db);
  final FileTransferService fileTransfer = FileTransferService();
  final ClipboardService clipboardService = ClipboardService();

  int _serverPort = 8080;
  String? _serverIp;

  bool isOtpExtractionEnabled = true;
  bool isClipboardSyncEnabled = true;
  final List<Map<String, String>> otpHistory = [];

  static const String _otpPrefKey = 'server_otp_enabled';
  static const String _clipPrefKey = 'server_clipboard_enabled';
  static const String _pinPrefKey = 'server_pairing_pin';

  /// Stream to notify Desktop UI when an OTP code is received
  final _otpNotificationController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get otpNotificationStream => _otpNotificationController.stream;

  /// Set of device IDs that have successfully verified the PIN for this session
  final Set<String> _pairedDeviceIds = {};

  ServerState _state = ServerState.idle;
  ServerState get state => _state;

  final Map<String, ConnectedDeviceInfo> _connectedDevices = {};
  Map<String, ConnectedDeviceInfo> get connectedDevices => Map.unmodifiable(_connectedDevices);

  SyncScope _clientScope = SyncScope.both;
  SyncScope get clientScope => _clientScope;

  bool _deviceAllows(String deviceId, SyncScope requestedScope) {
    final deviceScope = _connectedDevices[deviceId]?.scope ?? _clientScope;
    return deviceScope == SyncScope.both || deviceScope == requestedScope;
  }

  final _stateController = StreamController<ServerState>.broadcast();
  Stream<ServerState> get stateStream => _stateController.stream;

  final _dataUpdatedController = StreamController<void>.broadcast();
  Stream<void> get dataUpdated => _dataUpdatedController.stream;

  int get connectedClientCount => (transport is WebSocketTransport) 
      ? (transport as WebSocketTransport).currentClientCount 
      : 0;

  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isOtpExtractionEnabled = prefs.getBool(_otpPrefKey) ?? true;
      isClipboardSyncEnabled = prefs.getBool(_clipPrefKey) ?? true;
      _dataUpdatedController.add(null);
    } catch (_) {}
  }

  Future<String?> _loadSavedPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_pinPrefKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinPrefKey, pin);
    } catch (_) {}
  }

  /// Ensure a pairing PIN exists, reusing the persisted PIN when available so
  /// a personal single-device setup doesn't have to re-pair every launch.
  Future<void> _ensurePin() async {
    final savedPin = await _loadSavedPin();
    if (savedPin != null && savedPin.length == 4 && int.tryParse(savedPin) != null) {
      pairing.setPin(savedPin);
    } else {
      await _savePin(pairing.generatePin());
    }
    _dataUpdatedController.add(null);
  }

  /// Generate a brand-new pairing PIN and persist it (used by the UI's reset action).
  Future<void> regeneratePin() async {
    await _savePin(pairing.generatePin());
    _dataUpdatedController.add(null);
  }

  Future<void> setOtpExtractionEnabled(bool enabled) async {
    isOtpExtractionEnabled = enabled;
    _dataUpdatedController.add(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_otpPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> setClipboardSyncEnabled(bool enabled) async {
    isClipboardSyncEnabled = enabled;
    if (!enabled) {
      clipboardService.stopMonitoring();
    } else {
      _startClipboardSync();
    }
    _dataUpdatedController.add(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clipPrefKey, enabled);
    } catch (_) {}
  }

  ServerSyncService(this.transport, this.discovery) {
    loadPreferences();
    transport.messages.listen((message) {
      _handleMessage(message).catchError((e) {
        debugPrint('Error handling message: $e');
      });
    });

    transport.connectionStatus.listen((connected) {
      if (connected) {
        _updateState(ServerState.connected);
      } else {
        if (connectedClientCount == 0) {
          _cleanUpAllDisconnectedDevices();
          pairing.reset();
          if (_state != ServerState.idle) {
            _updateState(ServerState.advertising);
            unawaited(_ensurePin());
          }
        }
      }
    });
  }

  void _updateState(ServerState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  Future<void> startServer({int port = 8080, String name = 'MySyncServer'}) async {
    _serverPort = port;
    await transport.startServer(port);
    await discovery.startAdvertising(name, port, type: 'mysync');
    if (discovery is NsdDiscoveryService) {
      await (discovery as NsdDiscoveryService).startBrowsing(type: 'mysync');
    } else {
      await discovery.startBrowsing();
    }
    await _fetchLocalIp();
    _updateState(ServerState.advertising);
    await _ensurePin();
    _startClipboardSync();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var iface in interfaces) {
        for (var addr in iface.addresses) {
          if (!addr.isLoopback) {
            _serverIp = addr.address;
            return;
          }
        }
      }
    } catch (_) {}
  }

  String? get currentPin => pairing.currentPin;

  /// JSON payload for generating pairing QR code
  String get qrPairingPayload {
    return jsonEncode({
      'address': _serverIp ?? '127.0.0.1',
      'port': _serverPort,
      'pin': pairing.currentPin ?? '',
    });
  }

  /// Initiates a connection from Server to a discovered Android Client device
  Future<void> connectToDiscoveredClient(DiscoveredServer client) async {
    try {
      await transport.connect(client.address, client.port);
      _updateState(ServerState.connected);
    } catch (e) {
      debugPrint("Failed to connect to client ${client.name}: $e");
    }
  }

  Future<void> _handleMessage(SyncMessage message) async {
    final devId = message.payload['device_id'] as String? ?? 'unknown';
    final devName = message.payload['device_name'] as String? ?? 'Android Device';

    switch (message.type) {
      case SyncMessageType.pairVerify:
        final pin = message.payload['pin'];
        final scopeStr = message.payload['scope'] as String?;
        SyncScope scope = SyncScope.both;
        if (scopeStr != null) {
          try {
            scope = SyncScope.values.byName(scopeStr);
            _clientScope = scope;
          } catch (_) {}
        }

        final pinValue = pin?.toString() ?? '';
        if (pairing.verifyPin(pinValue)) {
          _pairedDeviceIds.add(devId);
          _connectedDevices[devId] = ConnectedDeviceInfo(
            deviceId: devId,
            deviceName: devName,
            scope: scope,
          );
          _updateState(ServerState.paired);
          await transport.send(SyncMessage(
            type: SyncMessageType.pairVerify,
            payload: {'status': 'success'},
          ));
          _dataUpdatedController.add(null);
        } else {
          await transport.send(SyncMessage(
            type: SyncMessageType.pairVerify,
            payload: {'status': 'failed'},
          ));
        }
        break;

      case SyncMessageType.contactInfo:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.smsSim)) {
          await db.insertOrUpdateSim(message.payload);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected contactInfo payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.sms:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.smsSim)) {
          await db.insertOrUpdateSms(message.payload);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected sms payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.rawText:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.textFiles)) {
          await db.insertRawText(message.payload);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected rawText payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.fileHeader:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.textFiles)) {
          await fileTransfer.handleFileHeader(message.payload);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected fileHeader payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.fileChunk:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.textFiles)) {
          await fileTransfer.handleFileChunk(message.payload);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected fileChunk payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.smsBatch:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.smsSim)) {
          final records = (message.payload['records'] as List<dynamic>?) ?? [];
          final smsList = records.map((r) => Map<String, dynamic>.from(r as Map)).toList();
          await db.insertSmsBatch(smsList);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected smsBatch payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.contactInfoBatch:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.smsSim)) {
          final records = (message.payload['records'] as List<dynamic>?) ?? [];
          final sims = records.map((r) => Map<String, dynamic>.from(r as Map)).toList();
          await db.insertSimBatch(sims);
          _dataUpdatedController.add(null);
        } else {
          debugPrint("Rejected contactInfoBatch payload from unpaired device: $devId");
        }
        break;

      case SyncMessageType.clipboardSync:
        if (_pairedDeviceIds.contains(devId) && isClipboardSyncEnabled) {
          final clientScope = _connectedDevices[devId]?.scope ?? _clientScope;
          if (clientScope == SyncScope.both || clientScope == SyncScope.textFiles) {
            final text = message.payload['text'] as String?;
            if (text != null && text.isNotEmpty) {
              await clipboardService.setText(text);
            }
          }
        }
        break;

      case SyncMessageType.otpCode:
        if (_pairedDeviceIds.contains(devId) && _deviceAllows(devId, SyncScope.smsSim)) {
          final otp = message.payload['otp'] as String?;
          final sender = message.payload['sender'] as String? ?? 'SMS';
          if (otp != null && otp.isNotEmpty) {
            // Save to OTP history
            final entry = {
              'otp': otp,
              'sender': sender,
              'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
            };
            otpHistory.insert(0, entry);
            if (otpHistory.length > 20) otpHistory.removeLast();

            // Auto copy OTP directly to Windows Clipboard IF toggle is enabled!
            if (isOtpExtractionEnabled) {
              await clipboardService.setText(otp);
              _otpNotificationController.add({'otp': otp, 'sender': sender});
            }
            _dataUpdatedController.add(null);
          }
        }
        break;

      default:
        break;
    }
  }

  /// Send formatted raw text from Desktop to Android Client(s).
  Future<void> sendRawText(String text) async {
    final hasTextClient = _connectedDevices.values.any(
      (device) => device.scope == SyncScope.both || device.scope == SyncScope.textFiles,
    );
    if (text.trim().isEmpty) return;
    if (!hasTextClient) {
      throw StateError('No paired client has text and file sync enabled');
    }
    final payload = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'sender': 'Windows PC',
      'device_id': 'pc',
      'device_name': 'Windows PC',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insertRawText(payload);
    await transport.send(SyncMessage(
      type: SyncMessageType.rawText,
      payload: payload,
    ));
    _dataUpdatedController.add(null);
  }

  /// Send a file from Desktop to Android Client(s).
  Future<void> sendFile(File file) async {
    final hasTextClient = _connectedDevices.values.any(
      (device) => device.scope == SyncScope.both || device.scope == SyncScope.textFiles,
    );
    if (!hasTextClient) {
      throw StateError('No paired client has text and file sync enabled');
    }
    await fileTransfer.sendFile(
      file: file,
      sender: 'Windows PC',
      sendMessage: (msg) => transport.send(msg),
    );
    _dataUpdatedController.add(null);
  }

  void _cleanUpAllDisconnectedDevices() {
    // Keep the local history when a phone briefly leaves Wi-Fi. The database
    // has explicit clear/export actions; disconnecting must not erase history.
    _pairedDeviceIds.clear();
    _connectedDevices.clear();
    _dataUpdatedController.add(null);
  }

  Future<void> disconnectClient() async {
    _cleanUpAllDisconnectedDevices();
    await transport.disconnect();
    pairing.reset();
    await startServer();
  }

  void _startClipboardSync() {
    if (!isClipboardSyncEnabled) return;
    clipboardService.startMonitoring((newText) {
      final hasTextClient = _connectedDevices.values.any(
        (device) => device.scope == SyncScope.both || device.scope == SyncScope.textFiles,
      );
      if (hasTextClient && isClipboardSyncEnabled) {
        transport.send(SyncMessage(
          type: SyncMessageType.clipboardSync,
          payload: {
            'text': newText,
            'device_id': 'pc',
            'device_name': 'Windows PC',
          },
        ));
      }
    });
  }

  Future<void> stopServer() async {
    _cleanUpAllDisconnectedDevices();
    clipboardService.stopMonitoring();
    await discovery.stopAdvertising();
    await discovery.stopBrowsing();
    await transport.disconnect();
    _updateState(ServerState.idle);
  }

  Future<void> dispose() async {
    await stopServer();
    clipboardService.dispose();
    fileTransfer.dispose();
    _stateController.close();
    _dataUpdatedController.close();
    _otpNotificationController.close();
  }
}
