import '../models/device_profile.dart';
import '../models/discovery_health.dart';

class DiscoveryPacketCodec {
  const DiscoveryPacketCodec._();

  static bool isSelfPayload(
    Map<String, dynamic> json, {
    required String localDeviceId,
  }) {
    final senderId = (json['deviceId'] as String?) ?? '';
    return senderId.isNotEmpty && senderId == localDeviceId;
  }

  static Map<String, dynamic> buildPayload({
    required String type,
    required String protocolVersion,
    required String deviceId,
    required String nickname,
    required String platform,
    required int activePort,
    int? securePort,
    required String certFingerprint,
    required String appVersion,
    required int requestPort,
    List<String> capabilities = const <String>[],
    String preferredAddressFamily = 'ipv4',
    DateTime? timestamp,
  }) {
    return <String, dynamic>{
      'type': type,
      'protocol': protocolVersion,
      'protocolVersion': protocolVersion,
      'deviceId': deviceId,
      'nickname': nickname,
      'platform': platform,
      'activePort': activePort,
      if (securePort != null && securePort > 0) 'securePort': securePort,
      'certFingerprint': certFingerprint,
      'appVersion': appVersion,
      'requestPort': requestPort,
      'capabilities': capabilities,
      'preferredAddressFamily': preferredAddressFamily,
      'timestamp': (timestamp ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }

  static DeviceProfile? tryParseProfile(
    Map<String, dynamic> json,
    String ipAddress, {
    required String protocolVersion,
  }) {
    try {
      final advertisedProtocol =
          (json['protocol'] as String?) ??
          (json['protocolVersion'] as String?) ??
          '';
      if (advertisedProtocol != protocolVersion) {
        return null;
      }
      final deviceId = (json['deviceId'] as String?) ?? '';
      final nickname = (json['nickname'] as String?) ?? '';
      final certFingerprint = (json['certFingerprint'] as String?) ?? '';
      final activePort = (json['activePort'] as num?)?.toInt() ?? 0;
      final securePort = (json['securePort'] as num?)?.toInt();
      if (deviceId.isEmpty ||
          nickname.isEmpty ||
          certFingerprint.isEmpty ||
          activePort <= 0) {
        return null;
      }
      return DeviceProfile(
        deviceId: deviceId,
        nickname: nickname,
        platform: (json['platform'] as String?) ?? 'unknown',
        ipAddress: ipAddress,
        ipAddresses: <String>[ipAddress],
        activePort: activePort,
        securePort: securePort,
        certFingerprint: certFingerprint,
        appVersion: (json['appVersion'] as String?) ?? '',
        protocolVersion: advertisedProtocol,
        capabilities:
            ((json['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
                .map((item) => item.toString())
                .where((item) => item.trim().isNotEmpty)
                .toList(growable: false),
        preferredAddressFamily:
            (json['preferredAddressFamily'] as String?) ??
            (ipAddress.contains(':') ? 'ipv6' : 'ipv4'),
        lastSeen: DateTime.now(),
        discoverySources: <DeviceDiscoverySource>[
          DeviceDiscoverySource(
            backendKind: DiscoveryBackendKind.udpLan,
            ipAddresses: <String>[ipAddress],
            activePort: activePort,
            securePort: securePort,
            preferredAddressFamily:
                (json['preferredAddressFamily'] as String?) ??
                (ipAddress.contains(':') ? 'ipv6' : 'ipv4'),
            lastSeen: DateTime.now(),
          ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
