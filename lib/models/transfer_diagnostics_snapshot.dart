import 'transfer_models.dart';

enum PeerAvailabilityStatus {
  unknown,
  checking,
  ready,
  incompatible,
  unreachable,
  securityFailure,
}

class PeerAvailabilitySnapshot {
  const PeerAvailabilitySnapshot({
    required this.deviceId,
    required this.nickname,
    required this.status,
    required this.updatedAt,
    this.selectedAddress,
    this.selectedPort,
    this.addressFamily,
    this.errorMessage,
    this.protocolVersion,
    this.appVersion,
    this.capabilities = const <String>[],
  });

  final String deviceId;
  final String nickname;
  final PeerAvailabilityStatus status;
  final DateTime updatedAt;
  final String? selectedAddress;
  final int? selectedPort;
  final String? addressFamily;
  final String? errorMessage;
  final String? protocolVersion;
  final String? appVersion;
  final List<String> capabilities;

  bool get isSendReady => status == PeerAvailabilityStatus.ready;

  PeerAvailabilitySnapshot copyWith({
    String? deviceId,
    String? nickname,
    PeerAvailabilityStatus? status,
    DateTime? updatedAt,
    Object? selectedAddress = _sentinel,
    Object? selectedPort = _sentinel,
    Object? addressFamily = _sentinel,
    Object? errorMessage = _sentinel,
    Object? protocolVersion = _sentinel,
    Object? appVersion = _sentinel,
    List<String>? capabilities,
  }) {
    return PeerAvailabilitySnapshot(
      deviceId: deviceId ?? this.deviceId,
      nickname: nickname ?? this.nickname,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedAddress: identical(selectedAddress, _sentinel)
          ? this.selectedAddress
          : selectedAddress as String?,
      selectedPort: identical(selectedPort, _sentinel)
          ? this.selectedPort
          : selectedPort as int?,
      addressFamily: identical(addressFamily, _sentinel)
          ? this.addressFamily
          : addressFamily as String?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      protocolVersion: identical(protocolVersion, _sentinel)
          ? this.protocolVersion
          : protocolVersion as String?,
      appVersion: identical(appVersion, _sentinel)
          ? this.appVersion
          : appVersion as String?,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}

class TransferDiagnosticsSnapshot {
  const TransferDiagnosticsSnapshot({
    required this.contextId,
    required this.peerDeviceId,
    required this.peerNickname,
    required this.isIncoming,
    required this.stage,
    required this.updatedAt,
    this.selectedAddress,
    this.selectedPort,
    this.addressFamily,
    this.tlsFingerprintVerified,
    this.lastHttpRoute,
    this.lastHttpStatusCode,
    this.offerStatus,
    this.decisionStatus,
    this.uploadStatus,
    this.terminalReason,
    this.errorMessage,
    this.logFilePath,
  });

  final String contextId;
  final String peerDeviceId;
  final String peerNickname;
  final bool isIncoming;
  final TransferStage stage;
  final DateTime updatedAt;
  final String? selectedAddress;
  final int? selectedPort;
  final String? addressFamily;
  final bool? tlsFingerprintVerified;
  final String? lastHttpRoute;
  final int? lastHttpStatusCode;
  final String? offerStatus;
  final TransferDecisionStatus? decisionStatus;
  final String? uploadStatus;
  final TransferTerminalReason? terminalReason;
  final String? errorMessage;
  final String? logFilePath;

  TransferDiagnosticsSnapshot copyWith({
    String? contextId,
    String? peerDeviceId,
    String? peerNickname,
    bool? isIncoming,
    TransferStage? stage,
    DateTime? updatedAt,
    Object? selectedAddress = _sentinel,
    Object? selectedPort = _sentinel,
    Object? addressFamily = _sentinel,
    Object? tlsFingerprintVerified = _sentinel,
    Object? lastHttpRoute = _sentinel,
    Object? lastHttpStatusCode = _sentinel,
    Object? offerStatus = _sentinel,
    Object? decisionStatus = _sentinel,
    Object? uploadStatus = _sentinel,
    Object? terminalReason = _sentinel,
    Object? errorMessage = _sentinel,
    Object? logFilePath = _sentinel,
  }) {
    return TransferDiagnosticsSnapshot(
      contextId: contextId ?? this.contextId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      peerNickname: peerNickname ?? this.peerNickname,
      isIncoming: isIncoming ?? this.isIncoming,
      stage: stage ?? this.stage,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedAddress: identical(selectedAddress, _sentinel)
          ? this.selectedAddress
          : selectedAddress as String?,
      selectedPort: identical(selectedPort, _sentinel)
          ? this.selectedPort
          : selectedPort as int?,
      addressFamily: identical(addressFamily, _sentinel)
          ? this.addressFamily
          : addressFamily as String?,
      tlsFingerprintVerified: identical(tlsFingerprintVerified, _sentinel)
          ? this.tlsFingerprintVerified
          : tlsFingerprintVerified as bool?,
      lastHttpRoute: identical(lastHttpRoute, _sentinel)
          ? this.lastHttpRoute
          : lastHttpRoute as String?,
      lastHttpStatusCode: identical(lastHttpStatusCode, _sentinel)
          ? this.lastHttpStatusCode
          : lastHttpStatusCode as int?,
      offerStatus: identical(offerStatus, _sentinel)
          ? this.offerStatus
          : offerStatus as String?,
      decisionStatus: identical(decisionStatus, _sentinel)
          ? this.decisionStatus
          : decisionStatus as TransferDecisionStatus?,
      uploadStatus: identical(uploadStatus, _sentinel)
          ? this.uploadStatus
          : uploadStatus as String?,
      terminalReason: identical(terminalReason, _sentinel)
          ? this.terminalReason
          : terminalReason as TransferTerminalReason?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      logFilePath: identical(logFilePath, _sentinel)
          ? this.logFilePath
          : logFilePath as String?,
    );
  }
}

const Object _sentinel = Object();
