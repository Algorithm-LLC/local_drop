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
      if (broadcastAddress == null || broadcastAddress.isEmpty) {
        continue;
      }
      for (final port in scanPorts) {
        addTarget(broadcastAddress, port);
      }
    }

    return targets.values.toList(growable: false);
  }
}
