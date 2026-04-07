import 'dart:async';
import 'dart:io';

import '../core/constants/network_constants.dart';
import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import 'discovery_backend.dart';
import 'discovery_registry.dart';
import 'local_network_platform_service.dart';

class NativePlatformDiscoveryBackend implements DiscoveryBackend {
  NativePlatformDiscoveryBackend({
    required LocalNetworkPlatformService platformService,
    Duration? staleAfter,
    void Function(String message)? logger,
  }) : _platformService = platformService,
       _logger = logger,
       _registry = DiscoveryRegistry(
         staleAfter: staleAfter ?? NetworkConstants.discoveryStaleTimeout,
       );

  final LocalNetworkPlatformService _platformService;
  final void Function(String message)? _logger;
  final DiscoveryRegistry _registry;
  final StreamController<List<DeviceProfile>> _devicesController =
      StreamController<List<DeviceProfile>>.broadcast();
  final StreamController<DiscoveryHealth> _healthController =
      StreamController<DiscoveryHealth>.broadcast();

  DiscoveryHealth _health = DiscoveryHealth(
    backend: 'native',
    backendState: DiscoveryBackendState(
      activeBackends: <DiscoveryBackendKind>[_platformBackendKind()],
      peerCountsByBackend: <String, int>{},
      lastErrorsByBackend: <String, String?>{},
      lastLogsByBackend: <String, String?>{},
    ),
  );

  late String _deviceId;

  @override
  Stream<List<DeviceProfile>> get devicesStream => _devicesController.stream;

  @override
  Stream<DiscoveryHealth> get healthStream => _healthController.stream;

  @override
  List<DeviceProfile> get currentDevices => _registry.sorted();

  @override
  DiscoveryHealth get currentHealth => _health;

  @override
  bool get isRunning => _health.isRunning;

  @override
  DiscoveryBackendKind get backendKind => _platformBackendKind();

  @override
  Future<void> start({
    required String deviceId,
    required int activePort,
    int? securePort,
    required String Function() nicknameProvider,
    required String Function() fingerprintProvider,
    required String appVersion,
  }) async {
    _deviceId = deviceId;
    _setHealth(
      _health.copyWith(
        backend: 'native',
        isStarting: true,
        boundPort: activePort,
        lastError: null,
        lastPermissionIssue: null,
        hasBlockingIssue: false,
        backendState: DiscoveryBackendState(
          activeBackends: <DiscoveryBackendKind>[backendKind],
          healthyBackends: const <DiscoveryBackendKind>[],
          degradedBackends: const <DiscoveryBackendKind>[],
          peerCountsByBackend: <String, int>{backendKind.name: 0},
          lastErrorsByBackend: const <String, String?>{},
          lastLogsByBackend: const <String, String?>{},
          isStarting: true,
        ),
      ),
    );
    await _platformService.startNativeDiscovery(
      deviceId: deviceId,
      nickname: nicknameProvider(),
      fingerprint: fingerprintProvider(),
      activePort: activePort,
      securePort: securePort,
      appVersion: appVersion,
    );
  }

  @override
  Future<void> stop() async {
    await _platformService.stopNativeDiscovery();
    _registry.clear();
    _emitDevices();
    _setHealth(
      DiscoveryHealth(
        backend: 'native',
        backendState: DiscoveryBackendState(
          activeBackends: <DiscoveryBackendKind>[backendKind],
          peerCountsByBackend: <String, int>{backendKind.name: 0},
          lastErrorsByBackend: const <String, String?>{},
          lastLogsByBackend: const <String, String?>{},
        ),
      ),
    );
  }

  @override
  Future<void> announceNow({bool burst = false}) async {}

  @override
  Future<void> scanNow({bool burstAnnounce = false}) async {
    final snapshot = await _platformService.getNativeDiscoverySnapshot();
    if (snapshot == null) {
      throw StateError('Native discovery snapshot is unavailable.');
    }

    final now = DateTime.now();
    for (final peer in snapshot.peers.where(
      (item) => item.deviceId != _deviceId,
    )) {
      _registry.upsert(peer.copyWith(lastSeen: now));
    }
    _registry.removeStale(now);
    final devices = _registry.sorted();
    _emitDevices();

    final peerCount = devices.length;
    final state = _buildBackendState(snapshot: snapshot, peerCount: peerCount);
    final isHealthy = state.healthyBackends.contains(backendKind);

    _setHealth(
      _health.copyWith(
        backend: 'native',
        isStarting: false,
        isRunning: snapshot.running,
        isBrowsing: snapshot.browsing,
        isPublishing: snapshot.advertising,
        discoveredDeviceCount: peerCount,
        lastScanAt: now,
        lastError: snapshot.lastError,
        lastPermissionIssue: snapshot.lastPermissionIssue,
        lastBackendLogMessage: snapshot.lastBackendLogMessage,
        backendState: state,
        hasBlockingIssue: !isHealthy,
      ),
    );
    _log(
      'Native discovery snapshot refreshed with ${snapshot.peers.length} peer(s).',
    );
  }

  @override
  void dispose() {
    unawaited(stop());
    _devicesController.close();
    _healthController.close();
  }

  static DiscoveryBackendKind _platformBackendKind() {
    if (Platform.isAndroid) {
      return DiscoveryBackendKind.androidNsd;
    }
    return DiscoveryBackendKind.appleBonjour;
  }

  DiscoveryBackendState _buildBackendState({
    required NativeDiscoverySnapshot snapshot,
    required int peerCount,
  }) {
    final hasError = snapshot.lastError?.trim().isNotEmpty ?? false;
    final hasPermissionIssue =
        snapshot.lastPermissionIssue?.trim().isNotEmpty ?? false;
    final isOperational =
        snapshot.running ||
        snapshot.browsing ||
        snapshot.advertising ||
        peerCount > 0;
    final isHealthy = isOperational && !hasError && !hasPermissionIssue;
    final isDegraded =
        !isHealthy && (isOperational || hasError || hasPermissionIssue);

    return DiscoveryBackendState(
      activeBackends: <DiscoveryBackendKind>[backendKind],
      healthyBackends: isHealthy
          ? <DiscoveryBackendKind>[backendKind]
          : const <DiscoveryBackendKind>[],
      degradedBackends: isDegraded
          ? <DiscoveryBackendKind>[backendKind]
          : const <DiscoveryBackendKind>[],
      peerCountsByBackend: <String, int>{backendKind.name: peerCount},
      lastErrorsByBackend: <String, String?>{
        backendKind.name: snapshot.lastError,
      },
      lastLogsByBackend: <String, String?>{
        backendKind.name: snapshot.lastBackendLogMessage,
      },
      isRunning: snapshot.running,
      isBrowsing: snapshot.browsing,
      isPublishing: snapshot.advertising,
      lastError: snapshot.lastError,
      lastPermissionIssue: snapshot.lastPermissionIssue,
      lastBackendLogMessage: snapshot.lastBackendLogMessage,
    );
  }

  void _emitDevices() {
    if (_devicesController.isClosed) {
      return;
    }
    _devicesController.add(_registry.sorted());
  }

  void _setHealth(DiscoveryHealth next) {
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
