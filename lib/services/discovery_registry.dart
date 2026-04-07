import 'dart:collection';

import '../models/device_profile.dart';

class DiscoveryRegistry {
  DiscoveryRegistry({required this.staleAfter});

  final Duration staleAfter;
  final Map<String, DeviceProfile> _devices = <String, DeviceProfile>{};

  void upsert(DeviceProfile profile) {
    _devices[profile.deviceId] = profile;
  }

  void removeStale(DateTime now) {
    final stale = _devices.values
        .where((item) => now.difference(item.lastSeen) > staleAfter)
        .map((item) => item.deviceId)
        .toList(growable: false);
    for (final deviceId in stale) {
      _devices.remove(deviceId);
    }
  }

  UnmodifiableListView<DeviceProfile> sorted() {
    final list = _devices.values.toList(growable: false)
      ..sort((a, b) {
        final nick = a.nickname.toLowerCase().compareTo(
          b.nickname.toLowerCase(),
        );
        if (nick != 0) {
          return nick;
        }
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return UnmodifiableListView<DeviceProfile>(list);
  }

  DeviceProfile? byId(String deviceId) => _devices[deviceId];

  void clear() => _devices.clear();
}
