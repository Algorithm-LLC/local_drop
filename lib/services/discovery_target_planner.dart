import '../models/network_interface_snapshot.dart';

class DiscoverySendTarget {
  const DiscoverySendTarget({required this.address, required this.port});

  final String address;
  final int port;

  String get key => '$address:$port';
}

class DiscoveryTargetPlanner {
  const DiscoveryTargetPlanner._();

  static List<DiscoverySendTarget> buildTargets({
    required List<NetworkInterfaceSnapshot> interfaces,
    required List<int> scanPorts,
    required String multicastAddress,
    bool includeSubnetHosts = false,
  }) {
    final targets = <String, DiscoverySendTarget>{};

    void addTarget(String address, int port) {
      final target = DiscoverySendTarget(address: address, port: port);
      targets.putIfAbsent(target.key, () => target);
    }

    for (final port in scanPorts) {
      addTarget('255.255.255.255', port);
      addTarget(multicastAddress, port);
    }

    for (final snapshot in interfaces.where(
      (item) => item.isEligibleForDiscovery,
    )) {
      final broadcastAddress = snapshot.broadcastAddress;
      for (final port in scanPorts) {
        if (broadcastAddress != null && broadcastAddress.isNotEmpty) {
          addTarget(broadcastAddress, port);
        }
        if (includeSubnetHosts) {
          for (final host in _directDiscoveryHosts(snapshot)) {
            addTarget(host, port);
          }
        }
      }
    }

    return targets.values.toList(growable: false);
  }

  static Iterable<String> _directDiscoveryHosts(
    NetworkInterfaceSnapshot snapshot,
  ) sync* {
    final local = _parseIpv4Parts(snapshot.address);
    if (local == null) {
      return;
    }
    final effectivePrefix = snapshot.prefixLength < 24
        ? 24
        : snapshot.prefixLength > 30
        ? 30
        : snapshot.prefixLength;
    final ip = _partsToInt(local);
    final mask = effectivePrefix == 0
        ? 0
        : (0xFFFFFFFF << (32 - effectivePrefix)) & 0xFFFFFFFF;
    final network = ip & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);
    for (var host = network + 1; host < broadcast; host += 1) {
      if (host == ip) {
        continue;
      }
      yield _intToIpv4String(host);
    }
  }

  static List<int>? _parseIpv4Parts(String value) {
    final segments = value.split('.');
    if (segments.length != 4) {
      return null;
    }
    final parts = <int>[];
    for (final segment in segments) {
      final parsed = int.tryParse(segment);
      if (parsed == null || parsed < 0 || parsed > 255) {
        return null;
      }
      parts.add(parsed);
    }
    return parts;
  }

  static int _partsToInt(List<int> parts) {
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  static String _intToIpv4String(int value) {
    return <String>[
      ((value >> 24) & 0xFF).toString(),
      ((value >> 16) & 0xFF).toString(),
      ((value >> 8) & 0xFF).toString(),
      (value & 0xFF).toString(),
    ].join('.');
  }
}
