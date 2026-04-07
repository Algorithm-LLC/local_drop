import 'device_profile.dart';

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
