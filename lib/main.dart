import 'dart:io';
import 'package:flutter/material.dart';
import 'transport/websocket_transport.dart';
import 'transport/nsd_service.dart';
import 'client/client_sync_service.dart';
import 'server/server_sync_service.dart';
import 'client/ui/client_home_screen.dart';
import 'server/ui/server_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Initializer(),
    );
  }
}

class Initializer extends StatefulWidget {
  const Initializer({super.key});

  @override
  State<Initializer> createState() => _InitializerState();
}

class _InitializerState extends State<Initializer> {
  late dynamic _service;
  bool _isServer = false;

  @override
  void initState() {
    super.initState();
    final transport = WebSocketTransport();
    final discovery = NsdDiscoveryService();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _isServer = true;
      _service = ServerSyncService(transport, discovery);
    } else if (Platform.isAndroid || Platform.isIOS) {
      _isServer = false;
      _service = ClientSyncService(transport, discovery);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isServer) {
      return ServerHomeScreen(service: _service as ServerSyncService);
    } else {
      return ClientHomeScreen(service: _service as ClientSyncService);
    }
  }
}
