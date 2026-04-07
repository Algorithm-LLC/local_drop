import '../models/device_profile.dart';
import '../models/discovery_health.dart';

abstract class DiscoveryBackend {
  Stream<List<DeviceProfile>> get devicesStream;
  Stream<DiscoveryHealth> get healthStream;

  List<DeviceProfile> get currentDevices;
  DiscoveryHealth get currentHealth;
  bool get isRunning;
  DiscoveryBackendKind get backendKind;

  Future<void> start({
    required String deviceId,
    required int activePort,
    int? securePort,
    required String Function() nicknameProvider,
    required String Function() fingerprintProvider,
    required String appVersion,
  });

  Future<void> stop();

  Future<void> announceNow({bool burst = false});

  Future<void> scanNow({bool burstAnnounce = false});

  void dispose();
}
