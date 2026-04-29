import 'device_profile.dart';

enum PeerTrustStatus { untrusted, trusted, missingFingerprint, identityChanged }

class TrustedPeerRecord {
  const TrustedPeerRecord({
    required this.deviceId,
    required this.nickname,
    required this.certFingerprint,
    required this.firstTrustedAt,
    required this.lastVerifiedAt,
  });

  final String deviceId;
  final String nickname;
  final String certFingerprint;
  final DateTime firstTrustedAt;
  final DateTime lastVerifiedAt;

  TrustedPeerRecord copyWith({
    String? nickname,
    String? certFingerprint,
    DateTime? lastVerifiedAt,
  }) {
    return TrustedPeerRecord(
      deviceId: deviceId,
      nickname: nickname ?? this.nickname,
      certFingerprint: certFingerprint ?? this.certFingerprint,
      firstTrustedAt: firstTrustedAt,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'nickname': nickname,
      'certFingerprint': certFingerprint,
      'firstTrustedAt': firstTrustedAt.toUtc().toIso8601String(),
      'lastVerifiedAt': lastVerifiedAt.toUtc().toIso8601String(),
    };
  }

  factory TrustedPeerRecord.fromJson(Map<String, dynamic> json) {
    return TrustedPeerRecord(
      deviceId: (json['deviceId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      certFingerprint: (json['certFingerprint'] as String?) ?? '',
      firstTrustedAt:
          DateTime.tryParse((json['firstTrustedAt'] as String?) ?? '') ??
          DateTime.now(),
      lastVerifiedAt:
          DateTime.tryParse((json['lastVerifiedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class TransportVerifiedPeerLease {
  const TransportVerifiedPeerLease({
    required this.deviceId,
    required this.profile,
    required this.lastSuccessfulActivityAt,
    this.selectedAddress,
    this.selectedPort,
    this.addressFamily,
  });

  final String deviceId;
  final DeviceProfile profile;
  final DateTime lastSuccessfulActivityAt;
  final String? selectedAddress;
  final int? selectedPort;
  final String? addressFamily;

  TransportVerifiedPeerLease copyWith({
    String? deviceId,
    DeviceProfile? profile,
    DateTime? lastSuccessfulActivityAt,
    Object? selectedAddress = _sentinel,
    Object? selectedPort = _sentinel,
    Object? addressFamily = _sentinel,
  }) {
    return TransportVerifiedPeerLease(
      deviceId: deviceId ?? this.deviceId,
      profile: profile ?? this.profile,
      lastSuccessfulActivityAt:
          lastSuccessfulActivityAt ?? this.lastSuccessfulActivityAt,
      selectedAddress: identical(selectedAddress, _sentinel)
          ? this.selectedAddress
          : selectedAddress as String?,
      selectedPort: identical(selectedPort, _sentinel)
          ? this.selectedPort
          : selectedPort as int?,
      addressFamily: identical(addressFamily, _sentinel)
          ? this.addressFamily
          : addressFamily as String?,
    );
  }
}

class IncomingActionResult {
  const IncomingActionResult._({required this.success, this.message});

  const IncomingActionResult.success() : this._(success: true);

  const IncomingActionResult.failure(String message)
    : this._(success: false, message: message);

  final bool success;
  final String? message;
}

const Object _sentinel = Object();
