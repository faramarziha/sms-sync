import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models/sync_message.dart';
import 'sync_transport.dart';

class WebSocketTransport implements SyncTransport {
  final Set<WebSocket> _sockets = {};
  HttpServer? _server;
  Timer? _pingTimer;
  
  final _messageController = StreamController<SyncMessage>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _activeClientCountController = StreamController<int>.broadcast();

  @override
  Stream<SyncMessage> get messages => _messageController.stream;

  @override
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  Stream<int> get activeClientCount => _activeClientCountController.stream;
  int get currentClientCount => _sockets.length;

  void _ensurePingTimer() {
    if (_pingTimer != null && _pingTimer!.isActive) return;
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final toRemove = <WebSocket>[];
      for (var socket in _sockets) {
        if (socket.readyState == WebSocket.open) {
          try {
            socket.add('{"type":"ping"}');
          } catch (e) {
            toRemove.add(socket);
          }
        } else {
          toRemove.add(socket);
        }
      }
      for (var socket in toRemove) {
        _removeSocket(socket);
      }
    });
  }

  @override
  Future<void> startDiscovery() async {}

  @override
  Future<void> connect(String address, int port) async {
    try {
      final formattedHost = (address.contains(':') && !address.startsWith('['))
          ? '[$address]'
          : address;
      final uriString = 'ws://$formattedHost:$port';
      debugPrint("Attempting to connect to $uriString...");
      final socket = await WebSocket.connect(uriString)
          .timeout(const Duration(seconds: 10));
      debugPrint("Connected successfully to $uriString");
      
      _addSocket(socket);
    } catch (e) {
      debugPrint("Connection failed to ws://$address:$port: $e");
      if (_sockets.isEmpty) {
        _connectionStatusController.add(false);
      }
      rethrow;
    }
  }

  @override
  Future<void> startServer(int port) async {
    // Guard: close existing server before rebinding to prevent SocketException
    if (_server != null) {
      debugPrint("Server already bound on port, closing before rebind...");
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    debugPrint("Server listening on 0.0.0.0:$port");
    _server?.transform(WebSocketTransformer()).listen((WebSocket socket) {
      debugPrint("Incoming client socket connection accepted");
      _addSocket(socket);
    });
  }

  void _addSocket(WebSocket socket) {
    _sockets.add(socket);
    _connectionStatusController.add(true);
    _activeClientCountController.add(_sockets.length);
    _ensurePingTimer(); // Restart ping timer if it was cancelled by disconnect
    _listenToSocket(socket);
  }

  void _removeSocket(WebSocket socket) {
    _sockets.remove(socket);
    try {
      socket.close();
    } catch (_) {}
    _activeClientCountController.add(_sockets.length);
    if (_sockets.isEmpty) {
      _connectionStatusController.add(false);
    }
  }

  void _listenToSocket(WebSocket socket) {
    socket.listen(
      (data) {
        if (data is String) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              if (decoded['type'] == 'ping') {
                return;
              }
              final message = SyncMessage.fromJson(decoded);
              _messageController.add(message);
            }
          } catch (e) {
            debugPrint("Error decoding message: $e");
          }
        }
      },
      onDone: () => _removeSocket(socket),
      onError: (_) => _removeSocket(socket),
    );
  }

  @override
  Future<void> send(SyncMessage message) async {
    if (_sockets.isEmpty) {
      throw Exception('Socket not connected');
    }
    final encoded = message.encode();
    final toRemove = <WebSocket>[];
    for (var socket in _sockets) {
      if (socket.readyState == WebSocket.open) {
        try {
          socket.add(encoded);
        } catch (e) {
          toRemove.add(socket);
        }
      } else {
        toRemove.add(socket);
      }
    }
    for (var s in toRemove) {
      _removeSocket(s);
    }
  }

  @override
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    for (var socket in List.from(_sockets)) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _sockets.clear();
    await _server?.close();
    _server = null;
    _connectionStatusController.add(false);
    _activeClientCountController.add(0);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStatusController.close();
    _activeClientCountController.close();
  }
}
