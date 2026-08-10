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
  int? _currentAdvertisingPort;

  /// Cache of local IP addresses for self-discovery filtering
  final Set<String> _localAddresses = {};

  @override
  Stream<List<DiscoveredServer>> get discoveredServers => _discoveredServersController.stream;

  /// Refresh the set of local network addresses
  Future<void> _refreshLocalAddresses() async {
    _localAddresses.clear();
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.any);
      for (var iface in interfaces) {
        for (var addr in iface.addresses) {
          _localAddresses.add(addr.address);
        }
      }
    } catch (e) {
      debugPrint("Error listing network interfaces: $e");
    }
    _localAddresses.add('127.0.0.1');
    _localAddresses.add('::1');
    debugPrint("Local addresses for self-filter: $_localAddresses");
  }

  String? _selectBestAddress(Service service) {
    final addresses = service.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      // Prefer IPv4
      for (var addr in addresses) {
        try {
          if (addr.type == InternetAddressType.IPv4 && !addr.address.startsWith('127.')) {
            return addr.address;
          }
        } catch (_) {
          continue;
        }
      }
      // Fall back to IPv6
      for (var addr in addresses) {
        try {
          if (addr.type == InternetAddressType.IPv6) {
            return addr.address.split('%').first;
          }
        } catch (_) {
          continue;
        }
      }
    }
    return service.host;
  }

  /// Check if a discovered service is actually ourselves
  bool _isSelfDiscovered(Service service) {
    final name = service.name;
    // Check by advertising name
    if (name != null && _currentAdvertisingName != null) {
      // NSD may append sequence numbers like "MySyncServer (2)"
      if (name == _currentAdvertisingName || name.startsWith('$_currentAdvertisingName (')) {
        return true;
      }
    }
    // Check by IP + port match
    final address = _selectBestAddress(service);
    final port = service.port;
    if (address != null && port != null && _currentAdvertisingPort != null) {
      if (_localAddresses.contains(address) && port == _currentAdvertisingPort) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> startBrowsing({String type = defaultServiceType}) async {
    await stopBrowsing();
    _servers.clear();
    await _refreshLocalAddresses();
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
          
          // Ignore self-discovered instances (by name AND IP+port)
          if (_isSelfDiscovered(service)) {
            debugPrint("Filtered self-discovered service: '$name'");
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
    _currentAdvertisingPort = port;
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
    _currentAdvertisingPort = null;
  }

  Future<void> dispose() async {
    await stopBrowsing();
    await stopAdvertising();
    await _discoveredServersController.close();
  }
}
