enum TransferPayloadType {
  file,
  photo,
  video,
  folder,
  text,
  clipboard;

  static TransferPayloadType fromStorage(String value) {
    return TransferPayloadType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransferPayloadType.file,
    );
  }
}

enum TransferStatus {
  pendingApproval,
  approved,
  declined,
  inProgress,
  completed,
  failed,
  canceled,
}

enum TransferDecisionStatus {
  pending,
  accepted,
  declined,
  expired;

  static TransferDecisionStatus fromStorage(String value) {
    return TransferDecisionStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransferDecisionStatus.pending,
    );
  }
}

enum TransferStage {
  connecting,
  offerQueued,
  awaitingApproval,
  uploading,
  completing,
  failed,
}

enum TransferTerminalReason {
  discoveryVisibleButUnreachable,
  tlsVerificationFailed,
  pinVerificationFailed,
  approvalExpired,
  declined,
  uploadFailed,
  integrityCheckFailed,
  incompatibleProtocol,
  canceled,
  unknown;

  static TransferTerminalReason fromStorage(String value) {
    return TransferTerminalReason.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransferTerminalReason.unknown,
    );
  }
}

class TransferPinChallenge {
  const TransferPinChallenge({
    required this.algorithm,
    required this.saltBase64,
    required this.iterations,
    required this.nonce,
    required this.expiresAt,
  });

  final String algorithm;
  final String saltBase64;
  final int iterations;
  final String nonce;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'algorithm': algorithm,
      'saltBase64': saltBase64,
      'iterations': iterations,
      'nonce': nonce,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  factory TransferPinChallenge.fromJson(Map<String, dynamic> json) {
    return TransferPinChallenge(
      algorithm: (json['algorithm'] as String?) ?? '',
      saltBase64: (json['saltBase64'] as String?) ?? '',
      iterations: (json['iterations'] as num?)?.toInt() ?? 0,
      nonce: (json['nonce'] as String?) ?? '',
      expiresAt:
          DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class TransferPinAuth {
  const TransferPinAuth({
    required this.algorithm,
    required this.nonce,
    required this.proofBase64,
  });

  final String algorithm;
  final String nonce;
  final String proofBase64;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'algorithm': algorithm,
      'nonce': nonce,
      'proofBase64': proofBase64,
    };
  }

  factory TransferPinAuth.fromJson(Map<String, dynamic> json) {
    return TransferPinAuth(
      algorithm: (json['algorithm'] as String?) ?? '',
      nonce: (json['nonce'] as String?) ?? '',
      proofBase64: (json['proofBase64'] as String?) ?? '',
    );
  }
}

class TransferItem {
  const TransferItem({
    required this.id,
    required this.type,
    required this.name,
    required this.sizeBytes,
    required this.checksumSha256,
    this.sourcePath,
    this.textContent,
  });

  final String id;
  final TransferPayloadType type;
  final String name;
  final int sizeBytes;
  final String checksumSha256;
  final String? sourcePath;
  final String? textContent;

  bool get isText =>
      type == TransferPayloadType.text || type == TransferPayloadType.clipboard;

  String get displayName {
    if (type != TransferPayloadType.folder) {
      return name;
    }
    final lowerName = name.toLowerCase();
    if (!lowerName.endsWith('.zip') || name.length <= 4) {
      return name;
    }
    return name.substring(0, name.length - 4);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'name': name,
      'sizeBytes': sizeBytes,
      'checksumSha256': checksumSha256,
      'sourcePath': sourcePath,
      'textContent': textContent,
    };
  }

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      id: (json['id'] as String?) ?? '',
      type: TransferPayloadType.fromStorage((json['type'] as String?) ?? ''),
      name: (json['name'] as String?) ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      checksumSha256: (json['checksumSha256'] as String?) ?? '',
      sourcePath: json['sourcePath'] as String?,
      textContent: json['textContent'] as String?,
    );
  }
}

class TransferOffer {
  const TransferOffer({
    required this.transferId,
    required this.senderDeviceId,
    required this.senderNickname,
    required this.senderFingerprint,
    required this.senderAppVersion,
    required this.protocolVersion,
    required this.createdAt,
    required this.items,
    this.pinAuth,
  });

  final String transferId;
  final String senderDeviceId;
  final String senderNickname;
  final String senderFingerprint;
  final String senderAppVersion;
  final String protocolVersion;
  final DateTime createdAt;
  final List<TransferItem> items;
  final TransferPinAuth? pinAuth;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  TransferOffer copyWith({TransferPinAuth? pinAuth}) {
    return TransferOffer(
      transferId: transferId,
      senderDeviceId: senderDeviceId,
      senderNickname: senderNickname,
      senderFingerprint: senderFingerprint,
      senderAppVersion: senderAppVersion,
      protocolVersion: protocolVersion,
      createdAt: createdAt,
      items: items,
      pinAuth: pinAuth ?? this.pinAuth,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'senderDeviceId': senderDeviceId,
      'senderNickname': senderNickname,
      'senderFingerprint': senderFingerprint,
      'senderAppVersion': senderAppVersion,
      'protocolVersion': protocolVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'pinAuth': pinAuth?.toJson(),
    };
  }

  factory TransferOffer.fromJson(Map<String, dynamic> json) {
    return TransferOffer(
      transferId: (json['transferId'] as String?) ?? '',
      senderDeviceId: (json['senderDeviceId'] as String?) ?? '',
      senderNickname: (json['senderNickname'] as String?) ?? '',
      senderFingerprint: (json['senderFingerprint'] as String?) ?? '',
      senderAppVersion: (json['senderAppVersion'] as String?) ?? '',
      protocolVersion: (json['protocolVersion'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TransferItem.fromJson)
          .toList(growable: false),
      pinAuth: json['pinAuth'] is Map<String, dynamic>
          ? TransferPinAuth.fromJson(json['pinAuth'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TransferOfferAck {
  const TransferOfferAck({
    required this.transferId,
    required this.status,
    required this.expiresAt,
    required this.receiverAppVersion,
    required this.receiverProtocolVersion,
    required this.receiverCapabilities,
    this.reason,
  });

  final String transferId;
  final String status;
  final DateTime expiresAt;
  final String receiverAppVersion;
  final String receiverProtocolVersion;
  final List<String> receiverCapabilities;
  final String? reason;

  bool get isQueued => status == 'queued';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'status': status,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'receiverAppVersion': receiverAppVersion,
      'receiverProtocolVersion': receiverProtocolVersion,
      'receiverCapabilities': receiverCapabilities,
      'reason': reason,
    };
  }

  factory TransferOfferAck.fromJson(Map<String, dynamic> json) {
    return TransferOfferAck(
      transferId: (json['transferId'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'queued',
      expiresAt:
          DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
          DateTime.now(),
      receiverAppVersion: (json['receiverAppVersion'] as String?) ?? '',
      receiverProtocolVersion:
          (json['receiverProtocolVersion'] as String?) ?? '',
      receiverCapabilities:
          ((json['receiverCapabilities'] as List<dynamic>?) ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(growable: false),
      reason: json['reason'] as String?,
    );
  }
}

class TransferDecisionSnapshot {
  const TransferDecisionSnapshot({
    required this.transferId,
    required this.status,
    required this.expiresAt,
    this.reason,
  });

  final String transferId;
  final TransferDecisionStatus status;
  final DateTime expiresAt;
  final String? reason;

  bool get isTerminal =>
      status == TransferDecisionStatus.accepted ||
      status == TransferDecisionStatus.declined ||
      status == TransferDecisionStatus.expired;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'status': status.name,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'reason': reason,
    };
  }

  factory TransferDecisionSnapshot.fromJson(Map<String, dynamic> json) {
    return TransferDecisionSnapshot(
      transferId: (json['transferId'] as String?) ?? '',
      status: TransferDecisionStatus.fromStorage(
        (json['status'] as String?) ?? TransferDecisionStatus.pending.name,
      ),
      expiresAt:
          DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
          DateTime.now(),
      reason: json['reason'] as String?,
    );
  }
}

class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.peerDeviceId,
    required this.peerNickname,
    required this.isIncoming,
    required this.status,
    required this.totalBytes,
    required this.transferredBytes,
    required this.startedAt,
    required this.updatedAt,
    this.stage,
    this.terminalReason,
    this.errorMessage,
  });

  final String transferId;
  final String peerDeviceId;
  final String peerNickname;
  final bool isIncoming;
  final TransferStatus status;
  final int totalBytes;
  final int transferredBytes;
  final DateTime startedAt;
  final DateTime updatedAt;
  final TransferStage? stage;
  final TransferTerminalReason? terminalReason;
  final String? errorMessage;

  double get completion => totalBytes <= 0 ? 0 : transferredBytes / totalBytes;

  double get bytesPerSecond {
    final elapsedMs = updatedAt.difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) {
      return 0;
    }
    return transferredBytes / (elapsedMs / 1000);
  }

  Duration? get eta {
    final speed = bytesPerSecond;
    if (speed <= 0 || transferredBytes >= totalBytes) {
      return null;
    }
    return Duration(seconds: ((totalBytes - transferredBytes) / speed).round());
  }

  TransferProgress copyWith({
    String? transferId,
    String? peerDeviceId,
    String? peerNickname,
    bool? isIncoming,
    TransferStatus? status,
    int? totalBytes,
    int? transferredBytes,
    DateTime? startedAt,
    DateTime? updatedAt,
    Object? stage = _sentinel,
    Object? terminalReason = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return TransferProgress(
      transferId: transferId ?? this.transferId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      peerNickname: peerNickname ?? this.peerNickname,
      isIncoming: isIncoming ?? this.isIncoming,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      stage: identical(stage, _sentinel) ? this.stage : stage as TransferStage?,
      terminalReason: identical(terminalReason, _sentinel)
          ? this.terminalReason
          : terminalReason as TransferTerminalReason?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class TransferComplete {
  const TransferComplete({
    required this.transferId,
    required this.completedAt,
    required this.itemChecksums,
  });

  final String transferId;
  final DateTime completedAt;
  final Map<String, String> itemChecksums;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'completedAt': completedAt.toUtc().toIso8601String(),
      'itemChecksums': itemChecksums,
    };
  }

  factory TransferComplete.fromJson(Map<String, dynamic> json) {
    return TransferComplete(
      transferId: (json['transferId'] as String?) ?? '',
      completedAt:
          DateTime.tryParse((json['completedAt'] as String?) ?? '') ??
          DateTime.now(),
      itemChecksums:
          ((json['itemChecksums'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{})
              .map((key, value) => MapEntry(key, value.toString())),
    );
  }
}

class TransferRecord {
  const TransferRecord({
    required this.transferId,
    required this.peerDeviceId,
    required this.peerNickname,
    required this.isIncoming,
    required this.items,
    required this.status,
    required this.totalBytes,
    required this.transferredBytes,
    required this.startedAt,
    required this.endedAt,
    this.stage,
    this.terminalReason,
    this.errorMessage,
  });

  final String transferId;
  final String peerDeviceId;
  final String peerNickname;
  final bool isIncoming;
  final List<TransferItem> items;
  final TransferStatus status;
  final int totalBytes;
  final int transferredBytes;
  final DateTime startedAt;
  final DateTime endedAt;
  final TransferStage? stage;
  final TransferTerminalReason? terminalReason;
  final String? errorMessage;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'peerDeviceId': peerDeviceId,
      'peerNickname': peerNickname,
      'isIncoming': isIncoming,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'status': status.name,
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'stage': stage?.name,
      'terminalReason': terminalReason?.name,
      'errorMessage': errorMessage,
    };
  }

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    final stageName = json['stage'] as String?;
    final terminalReasonName = json['terminalReason'] as String?;
    return TransferRecord(
      transferId: (json['transferId'] as String?) ?? '',
      peerDeviceId: (json['peerDeviceId'] as String?) ?? '',
      peerNickname: (json['peerNickname'] as String?) ?? '',
      isIncoming: (json['isIncoming'] as bool?) ?? false,
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TransferItem.fromJson)
          .toList(growable: false),
      status: TransferStatus.values.firstWhere(
        (item) => item.name == (json['status'] as String?),
        orElse: () => TransferStatus.failed,
      ),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      transferredBytes: (json['transferredBytes'] as num?)?.toInt() ?? 0,
      startedAt:
          DateTime.tryParse((json['startedAt'] as String?) ?? '') ??
          DateTime.now(),
      endedAt:
          DateTime.tryParse((json['endedAt'] as String?) ?? '') ??
          DateTime.now(),
      stage: stageName == null
          ? null
          : TransferStage.values.firstWhere(
              (item) => item.name == stageName,
              orElse: () => TransferStage.failed,
            ),
      terminalReason: terminalReasonName == null
          ? null
          : TransferTerminalReason.fromStorage(terminalReasonName),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

class IncomingTransferSession {
  const IncomingTransferSession({
    required this.transferId,
    required this.senderDeviceId,
    required this.senderNickname,
    required this.senderFingerprint,
    required this.senderAppVersion,
    required this.protocolVersion,
    required this.items,
    required this.remoteAddress,
    required this.receivedAt,
    required this.expiresAt,
    required this.status,
    this.terminalReason,
    this.reason,
  });

  final String transferId;
  final String senderDeviceId;
  final String senderNickname;
  final String senderFingerprint;
  final String senderAppVersion;
  final String protocolVersion;
  final List<TransferItem> items;
  final String remoteAddress;
  final DateTime receivedAt;
  final DateTime expiresAt;
  final TransferDecisionStatus status;
  final TransferTerminalReason? terminalReason;
  final String? reason;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  bool get isPending => status == TransferDecisionStatus.pending;

  Duration get remainingApprovalTime {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  IncomingTransferSession copyWith({
    String? transferId,
    String? senderDeviceId,
    String? senderNickname,
    String? senderFingerprint,
    String? senderAppVersion,
    String? protocolVersion,
    List<TransferItem>? items,
    String? remoteAddress,
    DateTime? receivedAt,
    DateTime? expiresAt,
    TransferDecisionStatus? status,
    Object? terminalReason = _sentinel,
    Object? reason = _sentinel,
  }) {
    return IncomingTransferSession(
      transferId: transferId ?? this.transferId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      senderNickname: senderNickname ?? this.senderNickname,
      senderFingerprint: senderFingerprint ?? this.senderFingerprint,
      senderAppVersion: senderAppVersion ?? this.senderAppVersion,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      items: items ?? this.items,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      receivedAt: receivedAt ?? this.receivedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      terminalReason: identical(terminalReason, _sentinel)
          ? this.terminalReason
          : terminalReason as TransferTerminalReason?,
      reason: identical(reason, _sentinel) ? this.reason : reason as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transferId': transferId,
      'senderDeviceId': senderDeviceId,
      'senderNickname': senderNickname,
      'senderFingerprint': senderFingerprint,
      'senderAppVersion': senderAppVersion,
      'protocolVersion': protocolVersion,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'remoteAddress': remoteAddress,
      'receivedAt': receivedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'status': status.name,
      'terminalReason': terminalReason?.name,
      'reason': reason,
    };
  }

  factory IncomingTransferSession.fromJson(Map<String, dynamic> json) {
    return IncomingTransferSession(
      transferId: (json['transferId'] as String?) ?? '',
      senderDeviceId: (json['senderDeviceId'] as String?) ?? '',
      senderNickname: (json['senderNickname'] as String?) ?? '',
      senderFingerprint: (json['senderFingerprint'] as String?) ?? '',
      senderAppVersion: (json['senderAppVersion'] as String?) ?? '',
      protocolVersion: (json['protocolVersion'] as String?) ?? '',
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TransferItem.fromJson)
          .toList(growable: false),
      remoteAddress: (json['remoteAddress'] as String?) ?? '',
      receivedAt:
          DateTime.tryParse((json['receivedAt'] as String?) ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
          DateTime.now(),
      status: TransferDecisionStatus.fromStorage(
        (json['status'] as String?) ?? TransferDecisionStatus.pending.name,
      ),
      terminalReason: (json['terminalReason'] as String?) == null
          ? null
          : TransferTerminalReason.fromStorage(
              json['terminalReason'] as String,
            ),
      reason: json['reason'] as String?,
    );
  }
}

const Object _sentinel = Object();
