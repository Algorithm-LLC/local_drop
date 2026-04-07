import '../core/constants/network_constants.dart';
import 'discovery_health.dart';

class DeviceDiscoverySource {
  const DeviceDiscoverySource({
    required this.backendKind,
    required this.ipAddresses,
    required this.activePort,
    this.securePort,
    required this.preferredAddressFamily,
    required this.lastSeen,
  });

  final DiscoveryBackendKind backendKind;
  final List<String> ipAddresses;
  final int activePort;
  final int? securePort;
  final String preferredAddressFamily;
  final DateTime lastSeen;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'backendKind': backendKind.name,
      'ipAddresses': ipAddresses,
      'activePort': activePort,
      'securePort': securePort,
      'preferredAddressFamily': preferredAddressFamily,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  factory DeviceDiscoverySource.fromJson(Map<String, dynamic> json) {
    return DeviceDiscoverySource(
      backendKind: DiscoveryBackendKind.fromName(
        (json['backendKind'] as String?) ?? DiscoveryBackendKind.udpLan.name,
      ),
      ipAddresses:
          ((json['ipAddresses'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false),
      activePort: (json['activePort'] as num?)?.toInt() ?? 0,
      securePort: (json['securePort'] as num?)?.toInt(),
      preferredAddressFamily:
          (json['preferredAddressFamily'] as String?) ?? 'ipv4',
      lastSeen:
          DateTime.tryParse((json['lastSeen'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class DeviceProfile {
  const DeviceProfile({
    required this.deviceId,
    required this.nickname,
    required this.platform,
    required this.ipAddress,
    required this.ipAddresses,
    required this.activePort,
    this.securePort,
    required this.certFingerprint,
    required this.appVersion,
    required this.protocolVersion,
    required this.capabilities,
    required this.preferredAddressFamily,
    required this.lastSeen,
    this.discoverySources = const <DeviceDiscoverySource>[],
  });

  final String deviceId;
  final String nickname;
  final String platform;
  final String ipAddress;
  final List<String> ipAddresses;
  final int activePort;
  final int? securePort;
  final String certFingerprint;
  final String appVersion;
  final String protocolVersion;
  final List<String> capabilities;
  final String preferredAddressFamily;
  final DateTime lastSeen;
  final List<DeviceDiscoverySource> discoverySources;

  bool get isProtocolCompatible =>
      protocolVersion.trim().isNotEmpty &&
      protocolVersion == NetworkConstants.protocolVersion;

  String get shortSuffix {
    if (deviceId.length <= 6) {
      return deviceId.toUpperCase();
    }
    return deviceId.substring(deviceId.length - 6).toUpperCase();
  }

  Iterable<DiscoveryBackendKind> get contributingBackends =>
      discoverySources.map((item) => item.backendKind);

  DeviceProfile copyWith({
    String? deviceId,
    String? nickname,
    String? platform,
    String? ipAddress,
    List<String>? ipAddresses,
    int? activePort,
    Object? securePort = _sentinel,
    String? certFingerprint,
    String? appVersion,
    String? protocolVersion,
    List<String>? capabilities,
    String? preferredAddressFamily,
    DateTime? lastSeen,
    List<DeviceDiscoverySource>? discoverySources,
  }) {
    return DeviceProfile(
      deviceId: deviceId ?? this.deviceId,
      nickname: nickname ?? this.nickname,
      platform: platform ?? this.platform,
      ipAddress: ipAddress ?? this.ipAddress,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      activePort: activePort ?? this.activePort,
      securePort: identical(securePort, _sentinel)
          ? this.securePort
          : securePort as int?,
      certFingerprint: certFingerprint ?? this.certFingerprint,
      appVersion: appVersion ?? this.appVersion,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      capabilities: capabilities ?? this.capabilities,
      preferredAddressFamily:
          preferredAddressFamily ?? this.preferredAddressFamily,
      lastSeen: lastSeen ?? this.lastSeen,
      discoverySources: discoverySources ?? this.discoverySources,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'nickname': nickname,
      'platform': platform,
      'ipAddress': ipAddress,
      'ipAddresses': ipAddresses,
      'activePort': activePort,
      'securePort': securePort,
      'certFingerprint': certFingerprint,
      'appVersion': appVersion,
      'protocolVersion': protocolVersion,
      'capabilities': capabilities,
      'preferredAddressFamily': preferredAddressFamily,
      'lastSeen': lastSeen.toIso8601String(),
      'discoverySources': discoverySources
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  factory DeviceProfile.fromJson(Map<String, dynamic> json) {
    final ipAddress = (json['ipAddress'] as String?) ?? '';
    final ipAddresses =
        ((json['ipAddresses'] as List<dynamic>?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);
    return DeviceProfile(
      deviceId: (json['deviceId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? 'unknown',
      ipAddress: ipAddress,
      ipAddresses: ipAddresses.isEmpty && ipAddress.trim().isNotEmpty
          ? <String>[ipAddress]
          : ipAddresses,
      activePort: (json['activePort'] as num?)?.toInt() ?? 0,
      securePort: (json['securePort'] as num?)?.toInt(),
      certFingerprint: (json['certFingerprint'] as String?) ?? '',
      appVersion: (json['appVersion'] as String?) ?? '',
      protocolVersion: (json['protocolVersion'] as String?) ?? '',
      capabilities:
          ((json['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(growable: false),
      preferredAddressFamily:
          (json['preferredAddressFamily'] as String?) ?? 'ipv4',
      lastSeen:
          DateTime.tryParse((json['lastSeen'] as String?) ?? '') ??
          DateTime.now(),
      discoverySources:
          ((json['discoverySources'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(DeviceDiscoverySource.fromJson)
              .toList(growable: false),
    );
  }
}

const Object _sentinel = Object();
