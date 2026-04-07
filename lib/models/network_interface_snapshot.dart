import 'dart:io';

class NetworkInterfaceSnapshot {
  const NetworkInterfaceSnapshot({
    required this.interfaceName,
    required this.address,
    required this.prefixLength,
  });

  final String interfaceName;
  final String address;
  final int prefixLength;

  InternetAddress? get internetAddress => InternetAddress.tryParse(address);

  bool get isLoopback {
    final parts = _parseIpv4Parts(address);
    return parts != null && parts[0] == 127;
  }

  bool get isLinkLocal {
    final parts = _parseIpv4Parts(address);
    return parts != null && parts[0] == 169 && parts[1] == 254;
  }

  bool get isMulticast {
    final parts = _parseIpv4Parts(address);
    return parts != null && parts[0] >= 224 && parts[0] <= 239;
  }

  bool get isAny {
    final parts = _parseIpv4Parts(address);
    return parts != null && parts.every((part) => part == 0);
  }

  bool get isEligibleForDiscovery {
    return prefixLength >= 1 &&
        prefixLength <= 30 &&
        !isLoopback &&
        !isLinkLocal &&
        !isMulticast &&
        !isAny;
  }

  String? get broadcastAddress {
    final value = _computeBroadcastAddress(address, prefixLength);
    return value?.address;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'interfaceName': interfaceName,
      'address': address,
      'prefixLength': prefixLength,
      'broadcastAddress': broadcastAddress,
    };
  }

  factory NetworkInterfaceSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return NetworkInterfaceSnapshot(
      interfaceName: (json['interfaceName'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      prefixLength: (json['prefixLength'] as num?)?.toInt() ?? 0,
    );
  }

  static InternetAddress? computeBroadcastAddress(
    String address,
    int prefixLength,
  ) {
    return _computeBroadcastAddress(address, prefixLength);
  }

  static InternetAddress? _computeBroadcastAddress(
    String address,
    int prefixLength,
  ) {
    final parts = _parseIpv4Parts(address);
    if (parts == null || prefixLength < 0 || prefixLength > 32) {
      return null;
    }
    final ip = _partsToInt(parts);
    final mask = prefixLength == 0
        ? 0
        : (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    final broadcast = (ip & mask) | (~mask & 0xFFFFFFFF);
    return InternetAddress(_intToIpv4String(broadcast));
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
