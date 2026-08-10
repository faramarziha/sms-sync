import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models/sync_message.dart';
import '../core/file_transfer_service.dart';
import '../transport/sync_transport.dart';
import '../transport/websocket_transport.dart';
import '../transport/nsd_service.dart';
import '../core/pairing_service.dart';
import 'db/database_service.dart';

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
  final FileTransferService fileTransfer = FileTransferService();

  ServerState _state = ServerState.idle;
  ServerState get state => _state;

  final Map<String, ConnectedDeviceInfo> _connectedDevices = {};
  Map<String, ConnectedDeviceInfo> get connectedDevices => Map.unmodifiable(_connectedDevices);

  SyncScope _clientScope = SyncScope.both;
  SyncScope get clientScope => _clientScope;

  final _stateController = StreamController<ServerState>.broadcast();
  Stream<ServerState> get stateStream => _stateController.stream;

  final _dataUpdatedController = StreamController<void>.broadcast();
  Stream<void> get dataUpdated => _dataUpdatedController.stream;

  int get connectedClientCount => (transport is WebSocketTransport) 
      ? (transport as WebSocketTransport).currentClientCount 
      : 0;

  ServerSyncService(this.transport, this.discovery) {
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
            pairing.generatePin();
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
    await transport.startServer(port);
    await discovery.startAdvertising(name, port, type: 'mysync');
    if (discovery is NsdDiscoveryService) {
      await (discovery as NsdDiscoveryService).startBrowsing(type: 'mysync');
    } else {
      await discovery.startBrowsing();
    }
    _updateState(ServerState.advertising);
    pairing.generatePin();
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

  String? get currentPin => pairing.currentPin;

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

        if (pairing.verifyPin(pin)) {
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
        if (pairing.isPaired) {
          await db.insertOrUpdateSim(message.payload);
          _dataUpdatedController.add(null);
        }
        break;

      case SyncMessageType.sms:
        if (pairing.isPaired) {
          await db.insertOrUpdateSms(message.payload);
          _dataUpdatedController.add(null);
        }
        break;

      case SyncMessageType.rawText:
        if (pairing.isPaired) {
          await db.insertRawText(message.payload);
          _dataUpdatedController.add(null);
        }
        break;

      case SyncMessageType.fileHeader:
        if (pairing.isPaired) {
          await fileTransfer.handleFileHeader(message.payload);
          _dataUpdatedController.add(null);
        }
        break;

      case SyncMessageType.fileChunk:
        if (pairing.isPaired) {
          await fileTransfer.handleFileChunk(message.payload);
          _dataUpdatedController.add(null);
        }
        break;

      default:
        break;
    }
  }

  /// Send formatted raw text from Desktop to Android Client(s).
  Future<void> sendRawText(String text) async {
    if (text.trim().isEmpty) return;
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
    await fileTransfer.sendFile(
      file: file,
      sender: 'Windows PC',
      sendMessage: (msg) => transport.send(msg),
    );
    _dataUpdatedController.add(null);
  }

  void _cleanUpAllDisconnectedDevices() {
    for (var devId in _connectedDevices.keys) {
      db.deleteDataForDevice(devId);
    }
    _connectedDevices.clear();
    _dataUpdatedController.add(null);
  }

  Future<void> disconnectClient() async {
    _cleanUpAllDisconnectedDevices();
    await transport.disconnect();
    pairing.reset();
  }

  Future<void> stopServer() async {
    _cleanUpAllDisconnectedDevices();
    await discovery.stopAdvertising();
    await discovery.stopBrowsing();
    await transport.disconnect();
    _updateState(ServerState.idle);
  }

  Future<void> dispose() async {
    await stopServer();
    fileTransfer.dispose();
    _stateController.close();
    _dataUpdatedController.close();
  }
}
