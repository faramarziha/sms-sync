import '../core/models/sync_message.dart';

abstract class SyncTransport {
  Stream<SyncMessage> get messages;
  Stream<bool> get connectionStatus;

  Future<void> startDiscovery();
  Future<void> connect(String address, int port);
  Future<void> send(SyncMessage message);
  Future<void> startServer(int port);
  Future<void> disconnect();
}

abstract class DiscoveryService {
  Stream<List<DiscoveredServer>> get discoveredServers;
  Future<void> startBrowsing({String type = 'mysync'});
  Future<void> stopBrowsing();
  Future<void> startAdvertising(String name, int port, {String type = 'mysync'});
  Future<void> stopAdvertising();
}

class DiscoveredServer {
  final String name;
  final String address;
  final int port;

  DiscoveredServer({
    required this.name,
    required this.address,
    required this.port,
  });
}
