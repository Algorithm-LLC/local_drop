import 'dart:async';
import 'dart:io';

import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import '../models/network_interface_snapshot.dart';
import 'composite_discovery_backend.dart';
import 'discovery_backend.dart';
import 'local_network_platform_service.dart';
import 'native_platform_discovery_backend.dart';
import 'udp_lan_discovery_backend.dart';

class DiscoveryService {
  DiscoveryService({
    required Future<List<NetworkInterfaceSnapshot>> Function() loadInterfaces,
    LocalNetworkPlatformService? platformService,
    void Function(String message)? logger,
  }) : _loadInterfaces = loadInterfaces,
       _platformService = platformService ?? LocalNetworkPlatformService(),
       _logger = logger;

  final Future<List<NetworkInterfaceSnapshot>> Function() _loadInterfaces;
  final LocalNetworkPlatformService _platformService;
  final void Function(String message)? _logger;

  final StreamController<List<DeviceProfile>> _devicesController =
      StreamController<List<DeviceProfile>>.broadcast();
  final StreamController<DiscoveryHealth> _healthController =
      StreamController<DiscoveryHealth>.broadcast();

  StreamSubscription<List<DeviceProfile>>? _backendDevicesSubscription;
  StreamSubscription<DiscoveryHealth>? _backendHealthSubscription;

  late final UdpLanDiscoveryBackend _udpBackend = UdpLanDiscoveryBackend(
    loadInterfaces: _loadInterfaces,
    logger: _log,
  );
  NativePlatformDiscoveryBackend? _nativeBackend;
  CompositeDiscoveryBackend? _compositeBackend;

  DiscoveryBackend? _selectedBackend;
  _DiscoveryConfig? _config;

  List<DeviceProfile> _devices = const <DeviceProfile>[];
  DiscoveryHealth _health = const DiscoveryHealth();
  bool _isPaused = false;
  DiscoveryPauseReason _pauseReason = DiscoveryPauseReason.none;
  bool _disposed = false;

  Stream<List<DeviceProfile>> get devicesStream => _devicesController.stream;
  Stream<DiscoveryHealth> get healthStream => _healthController.stream;
  List<DeviceProfile> get currentDevices => _devices;
  DiscoveryHealth get currentHealth => _health;
  bool get isRunning => _health.isRunning;
  int? get boundPort => _health.boundPort;

  Future<void> start({
    required String deviceId,
    required int activePort,
    int? securePort,
    required String Function() nicknameProvider,
    required String Function() fingerprintProvider,
    required String appVersion,
  }) async {
    _config = _DiscoveryConfig(
      deviceId: deviceId,
      activePort: activePort,
      securePort: securePort,
      nicknameProvider: nicknameProvider,
      fingerprintProvider: fingerprintProvider,
      appVersion: appVersion,
    );
    _isPaused = false;
    _pauseReason = DiscoveryPauseReason.none;

    final backend = _preferredBackend;
    await _selectBackend(backend);
    await backend.start(
      deviceId: deviceId,
      activePort: activePort,
      securePort: securePort,
      nicknameProvider: nicknameProvider,
      fingerprintProvider: fingerprintProvider,
      appVersion: appVersion,
    );
    _devices = backend.currentDevices;
    _emitDevices();
    _emitHealth(_decorateHealth(backend.currentHealth));
  }

  Future<void> stop() async {
    _config = null;
    _isPaused = false;
    _pauseReason = DiscoveryPauseReason.none;
    await _stopSelectedBackend();
    _devices = const <DeviceProfile>[];
    _emitDevices();
    _emitHealth(const DiscoveryHealth());
  }

  Future<void> pauseForBackground() async {
    if (!_isMobilePlatform || _config == null || _isPaused) {
      return;
    }
    _isPaused = true;
    _pauseReason = DiscoveryPauseReason.backgrounded;
    await _stopSelectedBackend();
    _devices = const <DeviceProfile>[];
    _emitDevices();
    _emitHealth(
      _decorateHealth(
        _health.copyWith(
          isRunning: false,
          isScanning: false,
          lastBackendLogMessage:
              'Discovery paused while the app is not in the foreground.',
        ),
      ),
    );
  }

  Future<void> resumeFromForeground() async {
    if (_config == null) {
      return;
    }
    _isPaused = false;
    _pauseReason = DiscoveryPauseReason.none;
  }

  Future<void> announceNow({bool burst = false}) async {
    if (_disposed || _config == null || _isPaused) {
      return;
    }

    var backend = _selectedBackend;
    if (backend == null) {
      await start(
        deviceId: _config!.deviceId,
        activePort: _config!.activePort,
        securePort: _config!.securePort,
        nicknameProvider: _config!.nicknameProvider,
        fingerprintProvider: _config!.fingerprintProvider,
        appVersion: _config!.appVersion,
      );
      backend = _selectedBackend;
      if (backend == null) {
        return;
      }
    }

    await backend.announceNow(burst: burst);
    _devices = backend.currentDevices;
    _emitDevices();
    _emitHealth(_decorateHealth(backend.currentHealth));
  }

  Future<void> scanNow({bool burstAnnounce = false}) async {
    if (_disposed || _config == null) {
      return;
    }
    if (_isPaused) {
      _emitHealth(
        _decorateHealth(
          _health.copyWith(
            isRunning: false,
            isScanning: false,
            lastBackendLogMessage:
                'Discovery is paused until the app returns to the foreground.',
          ),
        ),
      );
      return;
    }

    var backend = _selectedBackend;
    if (backend == null) {
      await start(
        deviceId: _config!.deviceId,
        activePort: _config!.activePort,
        securePort: _config!.securePort,
        nicknameProvider: _config!.nicknameProvider,
        fingerprintProvider: _config!.fingerprintProvider,
        appVersion: _config!.appVersion,
      );
      backend = _selectedBackend;
      if (backend == null) {
        return;
      }
    }

    await backend.scanNow(burstAnnounce: burstAnnounce);
    _devices = backend.currentDevices;
    _emitDevices();
    _emitHealth(_decorateHealth(backend.currentHealth));
  }

  void dispose() {
    _disposed = true;
    unawaited(_stopSelectedBackend());
    _compositeBackend?.dispose();
    _nativeBackend?.dispose();
    _udpBackend.dispose();
    unawaited(_devicesController.close());
    unawaited(_healthController.close());
  }

  DiscoveryBackend get _preferredBackend {
    if (_platformService.supportsNativeDiscovery &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      final native = _nativeBackend ??= NativePlatformDiscoveryBackend(
        platformService: _platformService,
        logger: _log,
      );
      return _compositeBackend ??= CompositeDiscoveryBackend(
        backends: <DiscoveryBackend>[_udpBackend, native],
        logger: _log,
      );
    }
    return _udpBackend;
  }

  Future<void> _selectBackend(DiscoveryBackend backend) async {
    if (identical(_selectedBackend, backend)) {
      await _backendDevicesSubscription?.cancel();
      await _backendHealthSubscription?.cancel();
      _bindBackend(backend);
      return;
    }
    await _stopSelectedBackend();
    _selectedBackend = backend;
    _bindBackend(backend);
  }

  Future<void> _stopSelectedBackend() async {
    await _backendDevicesSubscription?.cancel();
    await _backendHealthSubscription?.cancel();
    _backendDevicesSubscription = null;
    _backendHealthSubscription = null;

    final backend = _selectedBackend;
    _selectedBackend = null;
    if (backend != null) {
      await backend.stop();
    }
  }

  void _bindBackend(DiscoveryBackend backend) {
    _backendDevicesSubscription = backend.devicesStream.listen((devices) {
      _devices = devices;
      _emitDevices();
      _emitHealth(
        _decorateHealth(
          backend.currentHealth.copyWith(discoveredDeviceCount: devices.length),
        ),
      );
    });
    _backendHealthSubscription = backend.healthStream.listen((health) {
      _emitHealth(_decorateHealth(health));
    });
  }

  DiscoveryHealth _decorateHealth(DiscoveryHealth next) {
    return next.copyWith(
      isRunning: !_isPaused && next.isRunning,
      isStarting: !_isPaused && next.isStarting,
      isScanning: !_isPaused && next.isScanning,
      isBrowsing: !_isPaused && next.isBrowsing,
      isPublishing: !_isPaused && next.isPublishing,
      discoveredDeviceCount: _devices.length,
      isPaused: _isPaused,
      pauseReason: _pauseReason,
      hasBlockingIssue: !_isPaused && next.hasBlockingIssue,
      backendState: next.backendState.copyWith(
        isRunning: !_isPaused && next.backendState.isRunning,
        isStarting: !_isPaused && next.backendState.isStarting,
        isBrowsing: !_isPaused && next.backendState.isBrowsing,
        isPublishing: !_isPaused && next.backendState.isPublishing,
      ),
    );
  }

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  void _emitDevices() {
    if (_devicesController.isClosed) {
      return;
    }
    _devicesController.add(_devices);
  }

  void _emitHealth(DiscoveryHealth next) {
    _health = next;
    if (_healthController.isClosed) {
      return;
    }
    _healthController.add(next);
  }

  void _log(String message) {
    _logger?.call(message);
  }
}

class _DiscoveryConfig {
  const _DiscoveryConfig({
    required this.deviceId,
    required this.activePort,
    required this.securePort,
    required this.nicknameProvider,
    required this.fingerprintProvider,
    required this.appVersion,
  });

  final String deviceId;
  final int activePort;
  final int? securePort;
  final String Function() nicknameProvider;
  final String Function() fingerprintProvider;
  final String appVersion;
}
