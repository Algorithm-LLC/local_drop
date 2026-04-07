import 'dart:async';

import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import 'discovery_backend.dart';

class CompositeDiscoveryBackend implements DiscoveryBackend {
  CompositeDiscoveryBackend({
    required List<DiscoveryBackend> backends,
    void Function(String message)? logger,
  }) : _backends = List<DiscoveryBackend>.from(backends),
       _logger = logger;

  final List<DiscoveryBackend> _backends;
  final void Function(String message)? _logger;
  final StreamController<List<DeviceProfile>> _devicesController =
      StreamController<List<DeviceProfile>>.broadcast();
  final StreamController<DiscoveryHealth> _healthController =
      StreamController<DiscoveryHealth>.broadcast();
  final Map<DiscoveryBackendKind, List<DeviceProfile>> _devicesByBackend =
      <DiscoveryBackendKind, List<DeviceProfile>>{};
  final Map<DiscoveryBackendKind, DiscoveryHealth> _healthByBackend =
      <DiscoveryBackendKind, DiscoveryHealth>{};
  final Map<DiscoveryBackendKind, StreamSubscription<List<DeviceProfile>>>
  _deviceSubscriptions =
      <DiscoveryBackendKind, StreamSubscription<List<DeviceProfile>>>{};
  final Map<DiscoveryBackendKind, StreamSubscription<DiscoveryHealth>>
  _healthSubscriptions =
      <DiscoveryBackendKind, StreamSubscription<DiscoveryHealth>>{};

  List<DeviceProfile> _currentDevices = const <DeviceProfile>[];
  DiscoveryHealth _currentHealth = const DiscoveryHealth(backend: 'composite');

  @override
  Stream<List<DeviceProfile>> get devicesStream => _devicesController.stream;

  @override
  Stream<DiscoveryHealth> get healthStream => _healthController.stream;

  @override
  List<DeviceProfile> get currentDevices => _currentDevices;

  @override
  DiscoveryHealth get currentHealth => _currentHealth;

  @override
  bool get isRunning => _backends.any((backend) => backend.isRunning);

  @override
  DiscoveryBackendKind get backendKind => _backends.first.backendKind;

  @override
  Future<void> start({
    required String deviceId,
    required int activePort,
    int? securePort,
    required String Function() nicknameProvider,
    required String Function() fingerprintProvider,
    required String appVersion,
  }) async {
    await stop();
    _bindBackends();

    final errors = <String>[];
    var startedAny = false;
    for (final backend in _backends) {
      try {
        await backend.start(
          deviceId: deviceId,
          activePort: activePort,
          securePort: securePort,
          nicknameProvider: nicknameProvider,
          fingerprintProvider: fingerprintProvider,
          appVersion: appVersion,
        );
        _devicesByBackend[backend.backendKind] = backend.currentDevices;
        _healthByBackend[backend.backendKind] = backend.currentHealth;
        startedAny = true;
      } catch (error) {
        final message =
            '${backend.backendKind.name} failed to start: ${error.toString()}';
        _log(message);
        errors.add(message);
        _healthByBackend[backend.backendKind] = DiscoveryHealth(
          backend: _backendLabel(backend.backendKind),
          lastError: error.toString(),
          lastBackendLogMessage: message,
          hasBlockingIssue: true,
          backendState: DiscoveryBackendState(
            activeBackends: <DiscoveryBackendKind>[backend.backendKind],
            healthyBackends: const <DiscoveryBackendKind>[],
            degradedBackends: <DiscoveryBackendKind>[backend.backendKind],
            lastErrorsByBackend: <String, String?>{
              backend.backendKind.name: error.toString(),
            },
            lastLogsByBackend: <String, String?>{
              backend.backendKind.name: message,
            },
            lastError: error.toString(),
            lastBackendLogMessage: message,
          ),
        );
      }
    }

    _recompute();
    if (!startedAny) {
      throw StateError(
        errors.isEmpty
            ? 'No discovery backend could be started.'
            : errors.join(' | '),
      );
    }
  }

  @override
  Future<void> stop() async {
    final stopTasks = _backends.map((backend) async {
      try {
        await backend.stop();
      } catch (_) {
        // Ignore individual shutdown failures.
      }
    });
    await Future.wait(stopTasks);
    await _cancelSubscriptions();
    _devicesByBackend.clear();
    _healthByBackend.clear();
    _currentDevices = const <DeviceProfile>[];
    _currentHealth = const DiscoveryHealth(
      backend: 'composite',
      backendState: DiscoveryBackendState(),
    );
    _emitDevices();
    _emitHealth();
  }

  @override
  Future<void> announceNow({bool burst = false}) async {
    for (final backend in _backends) {
      await backend.announceNow(burst: burst);
      _devicesByBackend[backend.backendKind] = backend.currentDevices;
      _healthByBackend[backend.backendKind] = backend.currentHealth;
    }
    _recompute();
  }

  @override
  Future<void> scanNow({bool burstAnnounce = false}) async {
    final errors = <String>[];
    var succeeded = false;
    for (final backend in _backends) {
      try {
        await backend.scanNow(burstAnnounce: burstAnnounce);
        _devicesByBackend[backend.backendKind] = backend.currentDevices;
        _healthByBackend[backend.backendKind] = backend.currentHealth;
        succeeded = true;
      } catch (error) {
        final message = '${backend.backendKind.name}: ${error.toString()}';
        _log(message);
        errors.add(message);
      }
    }
    _recompute();
    if (!succeeded && errors.isNotEmpty) {
      throw StateError(errors.join(' | '));
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    _devicesController.close();
    _healthController.close();
  }

  void _bindBackends() {
    for (final backend in _backends) {
      _deviceSubscriptions[backend.backendKind] = backend.devicesStream.listen((
        devices,
      ) {
        _devicesByBackend[backend.backendKind] = devices;
        _recompute();
      });
      _healthSubscriptions[backend.backendKind] = backend.healthStream.listen((
        health,
      ) {
        _healthByBackend[backend.backendKind] = health;
        _recompute();
      });
    }
  }

  Future<void> _cancelSubscriptions() async {
    for (final subscription in _deviceSubscriptions.values) {
      await subscription.cancel();
    }
    for (final subscription in _healthSubscriptions.values) {
      await subscription.cancel();
    }
    _deviceSubscriptions.clear();
    _healthSubscriptions.clear();
  }

  void _recompute() {
    final mergedDevices = _mergeDevices();
    final nextHealth = _mergeHealth(mergedDevices);
    _currentDevices = mergedDevices;
    _currentHealth = nextHealth;
    _emitDevices();
    _emitHealth();
  }

  List<DeviceProfile> _mergeDevices() {
    final grouped = <String, List<_DiscoveredSourceProfile>>{};
    for (final entry in _devicesByBackend.entries) {
      final backendKind = entry.key;
      final devices = entry.value;
      for (final device in devices) {
        grouped
            .putIfAbsent(device.deviceId, () => <_DiscoveredSourceProfile>[])
            .add(
              _DiscoveredSourceProfile(
                backendKind: backendKind,
                profile: device,
              ),
            );
      }
    }

    final merged = grouped.values.map(_mergeProfiles).toList(growable: false)
      ..sort((a, b) {
        final nicknameCompare = a.nickname.toLowerCase().compareTo(
          b.nickname.toLowerCase(),
        );
        if (nicknameCompare != 0) {
          return nicknameCompare;
        }
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return merged;
  }

  DeviceProfile _mergeProfiles(List<_DiscoveredSourceProfile> sourceProfiles) {
    final sorted = List<_DiscoveredSourceProfile>.from(sourceProfiles)
      ..sort((a, b) {
        final lastSeenCompare = b.profile.lastSeen.compareTo(
          a.profile.lastSeen,
        );
        if (lastSeenCompare != 0) {
          return lastSeenCompare;
        }
        return _sourcePriority(
          a.backendKind,
        ).compareTo(_sourcePriority(b.backendKind));
      });
    final newest = sorted.first.profile;
    final canonical =
        sorted
            .where((item) => item.backendKind == DiscoveryBackendKind.udpLan)
            .cast<_DiscoveredSourceProfile?>()
            .firstWhere((item) => item != null, orElse: () => null) ??
        sorted.first;
    final ipAddresses = <String>[];
    final capabilities = <String>[];
    final discoverySources = <DeviceDiscoverySource>[];

    void addUnique(Iterable<String> values, List<String> target) {
      for (final value in values) {
        if (value.trim().isEmpty || target.contains(value)) {
          continue;
        }
        target.add(value);
      }
    }

    for (final source in sorted) {
      final profile = source.profile;
      discoverySources.add(
        DeviceDiscoverySource(
          backendKind: source.backendKind,
          ipAddresses: List<String>.from(profile.ipAddresses),
          activePort: profile.activePort,
          securePort: profile.securePort,
          preferredAddressFamily: profile.preferredAddressFamily,
          lastSeen: profile.lastSeen,
        ),
      );
      addUnique(profile.capabilities, capabilities);
    }

    final rankedAddresses = _rankAddresses(
      sorted,
      canonicalPreferredFamily: canonical.profile.preferredAddressFamily,
    );
    addUnique(rankedAddresses, ipAddresses);
    final primaryAddress = ipAddresses.isNotEmpty
        ? ipAddresses.first
        : newest.ipAddress;
    final preferredFamily = primaryAddress.contains(':') ? 'ipv6' : 'ipv4';

    return canonical.profile.copyWith(
      nickname: newest.nickname,
      platform: newest.platform,
      ipAddress: primaryAddress,
      ipAddresses: ipAddresses,
      securePort: newest.securePort ?? canonical.profile.securePort,
      certFingerprint: newest.certFingerprint,
      appVersion: newest.appVersion,
      protocolVersion: newest.protocolVersion,
      capabilities: capabilities,
      preferredAddressFamily: preferredFamily,
      lastSeen: newest.lastSeen,
      discoverySources: discoverySources,
    );
  }

  DiscoveryHealth _mergeHealth(List<DeviceProfile> mergedDevices) {
    final orderedKinds = _backends
        .map((item) => item.backendKind)
        .toList(growable: false);
    final peerCounts = <String, int>{};
    final errors = <String, String?>{};
    final logs = <String, String?>{};
    final healthyBackends = <DiscoveryBackendKind>[];
    final degradedBackends = <DiscoveryBackendKind>[];

    for (final kind in orderedKinds) {
      final health = _healthByBackend[kind];
      peerCounts[kind.name] = _devicesByBackend[kind]?.length ?? 0;
      errors[kind.name] = health?.lastError;
      logs[kind.name] = health?.lastBackendLogMessage;
      if (health == null) {
        continue;
      }
      if (_isBackendHealthy(kind, health)) {
        healthyBackends.add(kind);
      } else if (_isBackendDegraded(health)) {
        degradedBackends.add(kind);
      }
    }

    final lastErrorValues = errors.values
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    final lastLogValues = logs.values
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    final permissionIssues = orderedKinds
        .map((kind) => _healthByBackend[kind]?.lastPermissionIssue)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    final activeBackends = orderedKinds
        .where((kind) => _healthByBackend.containsKey(kind))
        .toList(growable: false);
    final primaryKind = orderedKinds.isEmpty ? null : orderedKinds.first;
    final primaryHealth = primaryKind == null
        ? null
        : _healthByBackend[primaryKind];
    final primaryHealthy =
        primaryKind != null &&
        primaryHealth != null &&
        _isBackendHealthy(primaryKind, primaryHealth);
    final allActiveBackendsBlocked =
        activeBackends.isNotEmpty &&
        healthyBackends.isEmpty &&
        (degradedBackends.isNotEmpty ||
            permissionIssues.isNotEmpty ||
            lastErrorValues.isNotEmpty);
    final hasBlockingIssue =
        (primaryKind != null &&
            activeBackends.contains(primaryKind) &&
            !primaryHealthy) ||
        allActiveBackendsBlocked;

    final lastScanTimes = _healthByBackend.values
        .map((item) => item.lastScanAt)
        .whereType<DateTime>()
        .toList(growable: false);
    final lastPublishTimes = _healthByBackend.values
        .map((item) => item.lastPublishAt)
        .whereType<DateTime>()
        .toList(growable: false);
    final resolvedFamily = mergedDevices.isNotEmpty
        ? mergedDevices.first.preferredAddressFamily
        : _firstNonEmptyString(
            _healthByBackend.values.map((item) => item.resolvedAddressFamily),
          );
    final combinedPermissionIssue = permissionIssues.isEmpty
        ? null
        : permissionIssues.join(' | ');
    final combinedError = lastErrorValues.isEmpty
        ? null
        : lastErrorValues.join(' | ');
    final globalPermissionIssue = hasBlockingIssue
        ? _firstNonEmptyString(<String?>[
            primaryHealth?.lastPermissionIssue,
            primaryHealth?.backendState.lastPermissionIssue,
            combinedPermissionIssue,
          ])
        : null;
    final globalError = hasBlockingIssue
        ? _firstNonEmptyString(<String?>[
            primaryHealth?.lastError,
            primaryHealth?.backendState.lastError,
            combinedError,
          ])
        : null;
    final globalLog = hasBlockingIssue
        ? _firstNonEmptyString(<String?>[
            primaryHealth?.lastBackendLogMessage,
            primaryHealth?.backendState.lastBackendLogMessage,
            lastLogValues.isEmpty ? null : lastLogValues.last,
          ])
        : _firstNonEmptyString(<String?>[
            primaryHealth?.lastBackendLogMessage,
            primaryHealth?.backendState.lastBackendLogMessage,
            lastLogValues.isEmpty ? null : lastLogValues.first,
          ]);

    return DiscoveryHealth(
      backend: activeBackends.map(_backendLabel).join(' + '),
      isRunning: _healthByBackend.values.any((item) => item.isRunning),
      isStarting: _healthByBackend.values.any((item) => item.isStarting),
      isScanning: _healthByBackend.values.any((item) => item.isScanning),
      isBrowsing: _healthByBackend.values.any((item) => item.isBrowsing),
      isPublishing: _healthByBackend.values.any((item) => item.isPublishing),
      boundPort: _firstNonNullInt(
        _healthByBackend.values.map((item) => item.boundPort),
      ),
      lastScanAt: lastScanTimes.isEmpty ? null : (lastScanTimes..sort()).last,
      lastPublishAt: lastPublishTimes.isEmpty
          ? null
          : (lastPublishTimes..sort()).last,
      packetsSent: _healthByBackend.values.fold<int>(
        0,
        (sum, item) => sum + item.packetsSent,
      ),
      packetsReceived: _healthByBackend.values.fold<int>(
        0,
        (sum, item) => sum + item.packetsReceived,
      ),
      interfaceCount: _healthByBackend.values.fold<int>(
        0,
        (sum, item) => sum + item.interfaceCount,
      ),
      lastScanTargetCount: _healthByBackend.values.fold<int>(
        0,
        (sum, item) => sum + item.lastScanTargetCount,
      ),
      discoveredDeviceCount: mergedDevices.length,
      lastError: globalError,
      lastPermissionIssue: globalPermissionIssue,
      resolvedAddressFamily: resolvedFamily,
      hasBlockingIssue: hasBlockingIssue,
      backendState: DiscoveryBackendState(
        activeBackends: activeBackends,
        healthyBackends: healthyBackends,
        degradedBackends: degradedBackends,
        peerCountsByBackend: peerCounts,
        lastErrorsByBackend: errors,
        lastLogsByBackend: logs,
        isRunning: _healthByBackend.values.any((item) => item.isRunning),
        isStarting: _healthByBackend.values.any((item) => item.isStarting),
        isBrowsing: _healthByBackend.values.any((item) => item.isBrowsing),
        isPublishing: _healthByBackend.values.any((item) => item.isPublishing),
        lastError: globalError,
        lastPermissionIssue: globalPermissionIssue,
        lastBackendLogMessage: globalLog,
      ),
      lastBackendLogMessage: globalLog,
    );
  }

  void _emitDevices() {
    if (_devicesController.isClosed) {
      return;
    }
    _devicesController.add(_currentDevices);
  }

  void _emitHealth() {
    if (_healthController.isClosed) {
      return;
    }
    _healthController.add(_currentHealth);
  }

  int? _firstNonNullInt(Iterable<int?> values) {
    for (final value in values) {
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _firstNonEmptyString(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool _isBackendHealthy(DiscoveryBackendKind kind, DiscoveryHealth health) {
    if (health.hasBlockingIssue) {
      return false;
    }
    final peerCount = health.backendState.peerCountsByBackend[kind.name] ?? 0;
    final hasIssue =
        (health.lastError?.trim().isNotEmpty ?? false) ||
        (health.lastPermissionIssue?.trim().isNotEmpty ?? false);
    final isOperational =
        health.isRunning ||
        health.isStarting ||
        health.isBrowsing ||
        health.isPublishing ||
        peerCount > 0 ||
        health.discoveredDeviceCount > 0;
    return isOperational && !hasIssue;
  }

  bool _isBackendDegraded(DiscoveryHealth health) {
    return health.hasBlockingIssue ||
        (health.lastError?.trim().isNotEmpty ?? false) ||
        (health.lastPermissionIssue?.trim().isNotEmpty ?? false) ||
        (!health.isRunning &&
            !health.isStarting &&
            health.discoveredDeviceCount == 0);
  }

  String _backendLabel(DiscoveryBackendKind kind) {
    return switch (kind) {
      DiscoveryBackendKind.androidNsd => 'android-nsd',
      DiscoveryBackendKind.appleBonjour => 'apple-bonjour',
      DiscoveryBackendKind.udpLan => 'udp-lan',
    };
  }

  void _log(String message) {
    _logger?.call(message);
  }

  List<String> _rankAddresses(
    List<_DiscoveredSourceProfile> sourceProfiles, {
    required String canonicalPreferredFamily,
  }) {
    final candidates = <_RankedAddressCandidate>[];
    final seen = <String>{};
    for (
      var sourceIndex = 0;
      sourceIndex < sourceProfiles.length;
      sourceIndex++
    ) {
      final source = sourceProfiles[sourceIndex];
      final profile = source.profile;
      final addresses = profile.ipAddresses.isEmpty
          ? <String>[profile.ipAddress]
          : profile.ipAddresses;
      for (
        var addressIndex = 0;
        addressIndex < addresses.length;
        addressIndex++
      ) {
        final address = addresses[addressIndex].trim();
        if (address.isEmpty || !seen.add(address)) {
          continue;
        }
        candidates.add(
          _RankedAddressCandidate(
            address: address,
            backendKind: source.backendKind,
            sourcePreferredFamily: profile.preferredAddressFamily,
            sourceIndex: sourceIndex,
            addressIndex: addressIndex,
          ),
        );
      }
    }

    candidates.sort((a, b) {
      final canonicalCompare = _familyWeight(
        canonicalPreferredFamily,
        a.address,
      ).compareTo(_familyWeight(canonicalPreferredFamily, b.address));
      if (canonicalCompare != 0) {
        return canonicalCompare;
      }
      final backendCompare = _sourcePriority(
        a.backendKind,
      ).compareTo(_sourcePriority(b.backendKind));
      if (backendCompare != 0) {
        return backendCompare;
      }
      final sourceFamilyCompare = _familyWeight(
        a.sourcePreferredFamily,
        a.address,
      ).compareTo(_familyWeight(b.sourcePreferredFamily, b.address));
      if (sourceFamilyCompare != 0) {
        return sourceFamilyCompare;
      }
      final addressFamilyCompare = _addressFamilyPriority(
        a.address,
      ).compareTo(_addressFamilyPriority(b.address));
      if (addressFamilyCompare != 0) {
        return addressFamilyCompare;
      }
      final sourceIndexCompare = a.sourceIndex.compareTo(b.sourceIndex);
      if (sourceIndexCompare != 0) {
        return sourceIndexCompare;
      }
      return a.addressIndex.compareTo(b.addressIndex);
    });
    return candidates.map((item) => item.address).toList(growable: false);
  }

  int _sourcePriority(DiscoveryBackendKind kind) {
    return switch (kind) {
      DiscoveryBackendKind.udpLan => 0,
      DiscoveryBackendKind.androidNsd => 1,
      DiscoveryBackendKind.appleBonjour => 1,
    };
  }

  int _familyWeight(String preferredFamily, String address) {
    return _addressFamily(address) == preferredFamily ? 0 : 1;
  }

  int _addressFamilyPriority(String address) {
    return _addressFamily(address) == 'ipv4' ? 0 : 1;
  }

  String _addressFamily(String address) {
    return address.contains(':') ? 'ipv6' : 'ipv4';
  }
}

class _DiscoveredSourceProfile {
  const _DiscoveredSourceProfile({
    required this.backendKind,
    required this.profile,
  });

  final DiscoveryBackendKind backendKind;
  final DeviceProfile profile;
}

class _RankedAddressCandidate {
  const _RankedAddressCandidate({
    required this.address,
    required this.backendKind,
    required this.sourcePreferredFamily,
    required this.sourceIndex,
    required this.addressIndex,
  });

  final String address;
  final DiscoveryBackendKind backendKind;
  final String sourcePreferredFamily;
  final int sourceIndex;
  final int addressIndex;
}
