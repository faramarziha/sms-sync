import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';
import 'sync_transport.dart';

class NsdDiscoveryService implements DiscoveryService {
  static const String defaultServiceType = 'mysync';
  
  final _discoveredServersController = StreamController<List<DiscoveredServer>>.broadcast();
  final Map<String, DiscoveredServer> _servers = {};
  
  Discovery? _discovery;
  Registration? _registration;
  String? _currentAdvertisingName;

  @override
  Stream<List<DiscoveredServer>> get discoveredServers => _discoveredServersController.stream;

  String? _selectBestAddress(Service service) {
    final addresses = service.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      for (var addr in addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.address.startsWith('127.')) {
          return addr.address;
        }
      }
      for (var addr in addresses) {
        if (addr.type == InternetAddressType.IPv6) {
          return addr.address.split('%').first;
        }
      }
    }
    return service.host;
  }

  @override
  Future<void> startBrowsing({String type = defaultServiceType}) async {
    await stopBrowsing();
    _servers.clear();
    final targetType = '_$type._tcp';
    debugPrint("NSD Auto-Browsing started for service type: $targetType");
    
    try {
      _discovery = await startDiscovery(targetType, ipLookupType: IpLookupType.any);
      _discovery?.addListener(() {
        final services = _discovery?.services ?? [];
        _servers.clear();
        for (var service in services) {
          final name = service.name;
          final address = _selectBestAddress(service);
          final port = service.port;
          
          // Ignore self-discovered instances
          if (name != null && name == _currentAdvertisingName) {
            continue;
          }

          if (name != null && address != null && port != null) {
            debugPrint("Auto-Discovered NSD Service: '$name' at $address:$port");
            _servers[name] = DiscoveredServer(
              name: name,
              address: address,
              port: port,
            );
          }
        }
        _discoveredServersController.add(_servers.values.toList());
      });
    } catch (e) {
      debugPrint("Error starting NSD discovery: $e");
    }
  }

  @override
  Future<void> stopBrowsing() async {
    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
      } catch (_) {}
      _discovery = null;
    }
  }

  @override
  Future<void> startAdvertising(String name, int port, {String type = defaultServiceType}) async {
    await stopAdvertising();
    _currentAdvertisingName = name;
    final targetType = '_$type._tcp';
    debugPrint("NSD Auto-Advertising started for '$name' on $targetType port $port");
    try {
      _registration = await register(
        Service(
          name: name,
          type: targetType,
          port: port,
        ),
      );
    } catch (e) {
      debugPrint("Error starting NSD advertising: $e");
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (_registration != null) {
      try {
        await unregister(_registration!);
      } catch (_) {}
      _registration = null;
    }
    _currentAdvertisingName = null;
  }

  Future<void> dispose() async {
    await stopBrowsing();
    await stopAdvertising();
    await _discoveredServersController.close();
  }
}
