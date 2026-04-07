import 'dart:io';

import 'package:flutter/services.dart';

import '../core/constants/network_constants.dart';
import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import '../models/network_interface_snapshot.dart';

class LocalNetworkPlatformService {
  static const MethodChannel _channel = MethodChannel('localdrop/network');

  bool get supportsNativeDiscovery {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<void> acquireMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {
      // Multicast lock improves Android discovery but should not crash startup.
    }
  }

  Future<void> releaseMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {
      // Ignore platform cleanup failures.
    }
  }

  Future<List<NetworkInterfaceSnapshot>> listActiveInterfaces() async {
    if (!Platform.isAndroid &&
        !Platform.isWindows &&
        !Platform.isIOS &&
        !Platform.isMacOS &&
        !Platform.isLinux) {
      return const <NetworkInterfaceSnapshot>[];
    }
    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'getActiveInterfaces',
      );
      if (raw == null) {
        return const <NetworkInterfaceSnapshot>[];
      }
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(NetworkInterfaceSnapshot.fromJson)
          .where(
            (item) =>
                item.interfaceName.trim().isNotEmpty &&
                item.address.trim().isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const <NetworkInterfaceSnapshot>[];
    }
  }

  Future<FirewallSetupResult> ensureFirewallRules() async {
    if (!Platform.isWindows) {
      return const FirewallSetupResult.notRequired();
    }
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'ensureFirewallRules',
      );
      if (raw == null) {
        return const FirewallSetupResult(
          status: FirewallSetupStatus.failed,
          message: 'No response from Windows firewall setup.',
        );
      }
      return FirewallSetupResult.fromJson(raw);
    } catch (error) {
      return FirewallSetupResult(
        status: FirewallSetupStatus.failed,
        message: error.toString(),
      );
    }
  }

  Future<void> startNativeDiscovery({
    required String deviceId,
    required String nickname,
    required String fingerprint,
    required int activePort,
    int? securePort,
    required String appVersion,
  }) async {
    if (!supportsNativeDiscovery) {
      throw UnsupportedError('Native discovery is not supported here.');
    }
    await _channel.invokeMethod<void>('startNativeDiscovery', <String, dynamic>{
      'deviceId': deviceId,
      'nickname': nickname,
      'certFingerprint': fingerprint,
      'activePort': activePort,
      if (securePort != null && securePort > 0) 'securePort': securePort,
      'appVersion': appVersion,
      'protocolVersion': NetworkConstants.protocolVersion,
      'capabilities': <String>[
        NetworkConstants.protocolCapabilityMdns,
        NetworkConstants.protocolCapabilityQueuedApproval,
        if (securePort != null && securePort > 0)
          NetworkConstants.protocolCapabilityHttpsTransfer,
      ],
    });
  }

  Future<void> stopNativeDiscovery() async {
    if (!supportsNativeDiscovery) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopNativeDiscovery');
    } catch (_) {
      // Ignore shutdown failures.
    }
  }

  Future<NativeDiscoverySnapshot?> getNativeDiscoverySnapshot() async {
    if (!supportsNativeDiscovery) {
      return null;
    }
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getNativeDiscoverySnapshot',
      );
      if (raw == null) {
        return null;
      }
      return NativeDiscoverySnapshot.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> activateAppWindow() async {
    if (!Platform.isMacOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('activateAppWindow');
    } catch (_) {
      // Foreground activation is best-effort only.
    }
  }
}

class NativeDiscoverySnapshot {
  const NativeDiscoverySnapshot({
    required this.running,
    required this.advertising,
    required this.browsing,
    required this.peers,
    this.lastError,
    this.lastPermissionIssue,
    this.lastBackendLogMessage,
  });

  final bool running;
  final bool advertising;
  final bool browsing;
  final List<DeviceProfile> peers;
  final String? lastError;
  final String? lastPermissionIssue;
  final String? lastBackendLogMessage;

  factory NativeDiscoverySnapshot.fromJson(Map<dynamic, dynamic> json) {
    final rawPeers = (json['peers'] as List<dynamic>?) ?? const <dynamic>[];
    final peers = rawPeers
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .map(_deviceProfileFromNativeJson)
        .whereType<DeviceProfile>()
        .toList(growable: false);
    return NativeDiscoverySnapshot(
      running: (json['running'] as bool?) ?? false,
      advertising: (json['advertising'] as bool?) ?? false,
      browsing: (json['browsing'] as bool?) ?? false,
      peers: peers,
      lastError: json['lastError'] as String?,
      lastPermissionIssue: json['lastPermissionIssue'] as String?,
      lastBackendLogMessage: json['lastBackendLogMessage'] as String?,
    );
  }

  static DeviceProfile? _deviceProfileFromNativeJson(
    Map<String, dynamic> json,
  ) {
    final deviceId = (json['deviceId'] as String?) ?? '';
    final nickname = (json['nickname'] as String?) ?? '';
    final ipAddresses =
        ((json['ipAddresses'] as List<dynamic>?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);
    if (deviceId.isEmpty || nickname.isEmpty || ipAddresses.isEmpty) {
      return null;
    }
    return DeviceProfile(
      deviceId: deviceId,
      nickname: nickname,
      platform: (json['platform'] as String?) ?? 'unknown',
      ipAddress: ipAddresses.first,
      ipAddresses: ipAddresses,
      activePort: (json['activePort'] as num?)?.toInt() ?? 0,
      securePort: (json['securePort'] as num?)?.toInt(),
      certFingerprint: (json['certFingerprint'] as String?) ?? '',
      appVersion: (json['appVersion'] as String?) ?? '',
      protocolVersion:
          (json['protocolVersion'] as String?) ??
          NetworkConstants.protocolVersion,
      capabilities:
          ((json['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(growable: false),
      preferredAddressFamily:
          (json['preferredAddressFamily'] as String?) ?? 'ipv4',
      lastSeen: DateTime.now(),
      discoverySources: <DeviceDiscoverySource>[
        DeviceDiscoverySource(
          backendKind: Platform.isAndroid
              ? DiscoveryBackendKind.androidNsd
              : DiscoveryBackendKind.appleBonjour,
          ipAddresses: ipAddresses,
          activePort: (json['activePort'] as num?)?.toInt() ?? 0,
          securePort: (json['securePort'] as num?)?.toInt(),
          preferredAddressFamily:
              (json['preferredAddressFamily'] as String?) ?? 'ipv4',
          lastSeen: DateTime.now(),
        ),
      ],
    );
  }
}
