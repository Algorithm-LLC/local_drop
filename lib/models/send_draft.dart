import 'dart:async';
import 'dart:io';

import 'device_profile.dart';
import 'transfer_models.dart';

enum SendStep { selectContent, chooseDevice }

enum SendFailureReason {
  noContent,
  recipientOffline,
  transferUnreachable,
  missingLocalFile,
  timeout,
  approvalExpired,
  invalidPin,
  certificateMismatch,
  integrityCheckFailed,
  rejected,
  incompatibleVersion,
  canceled,
  busy,
  unknown,
}

class SendAttemptResult {
  const SendAttemptResult._({
    required this.success,
    this.failureReason,
    this.details,
  });

  const SendAttemptResult.success()
    : success = true,
      failureReason = null,
      details = null;

  const SendAttemptResult.failure(SendFailureReason reason, {String? details})
    : this._(success: false, failureReason: reason, details: details);

  final bool success;
  final SendFailureReason? failureReason;
  final String? details;
}

class SendDraft {
  const SendDraft({
    required this.step,
    required this.items,
    required this.isSending,
  });

  const SendDraft.empty()
    : step = SendStep.selectContent,
      items = const <TransferItem>[],
      isSending = false;

  final SendStep step;
  final List<TransferItem> items;
  final bool isSending;

  bool get hasItems => items.isNotEmpty;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  SendDraft copyWith({
    SendStep? step,
    List<TransferItem>? items,
    bool? isSending,
  }) {
    return SendDraft(
      step: step ?? this.step,
      items: items ?? this.items,
      isSending: isSending ?? this.isSending,
    );
  }

  SendDraft addItems(List<TransferItem> additional) {
    if (additional.isEmpty) {
      return this;
    }
    final merged = <TransferItem>[...items];
    final signatures = items.map(_itemSignature).toSet();
    for (final item in additional) {
      final signature = _itemSignature(item);
      if (signatures.contains(signature)) {
        continue;
      }
      signatures.add(signature);
      merged.add(item);
    }
    return copyWith(items: merged);
  }

  SendDraft removeItem(String itemId) {
    final filtered = items
        .where((item) => item.id != itemId)
        .toList(growable: false);
    return copyWith(items: filtered);
  }

  SendDraft clear() {
    return const SendDraft.empty();
  }

  String _itemSignature(TransferItem item) {
    if (item.sourcePath != null && item.sourcePath!.isNotEmpty) {
      return 'path:${item.sourcePath}:${item.sizeBytes}:${item.checksumSha256}';
    }
    return 'text:${item.type.name}:${item.name}:${item.checksumSha256}:${item.textContent ?? ''}';
  }
}

Future<SendFailureReason?> validateSendDraftBeforeSend({
  required SendDraft draft,
  required DeviceProfile? recipient,
}) async {
  if (!draft.hasItems) {
    return SendFailureReason.noContent;
  }
  if (recipient == null) {
    return SendFailureReason.recipientOffline;
  }
  if (!recipient.isProtocolCompatible) {
    return SendFailureReason.incompatibleVersion;
  }
  for (final item in draft.items) {
    if (item.isText) {
      continue;
    }
    final path = item.sourcePath;
    if (path == null || path.isEmpty) {
      return SendFailureReason.missingLocalFile;
    }
    if (!await File(path).exists()) {
      return SendFailureReason.missingLocalFile;
    }
  }
  return null;
}

SendFailureReason mapSendFailure({
  required TransferStatus status,
  TransferTerminalReason? terminalReason,
  String? errorMessage,
}) {
  if (status == TransferStatus.canceled) {
    return SendFailureReason.canceled;
  }
  if (status == TransferStatus.declined) {
    return SendFailureReason.rejected;
  }
  switch (terminalReason) {
    case TransferTerminalReason.discoveryVisibleButUnreachable:
      return SendFailureReason.transferUnreachable;
    case TransferTerminalReason.tlsVerificationFailed:
      return SendFailureReason.certificateMismatch;
    case TransferTerminalReason.pinVerificationFailed:
      return SendFailureReason.invalidPin;
    case TransferTerminalReason.approvalExpired:
      return SendFailureReason.approvalExpired;
    case TransferTerminalReason.declined:
      return SendFailureReason.rejected;
    case TransferTerminalReason.uploadFailed:
      return SendFailureReason.timeout;
    case TransferTerminalReason.integrityCheckFailed:
      return SendFailureReason.integrityCheckFailed;
    case TransferTerminalReason.incompatibleProtocol:
      return SendFailureReason.incompatibleVersion;
    case TransferTerminalReason.canceled:
      return SendFailureReason.canceled;
    case TransferTerminalReason.unknown:
    case null:
      break;
  }
  final text = (errorMessage ?? '').toLowerCase();
  if (text.contains('timed out') || text.contains('timeout')) {
    return SendFailureReason.timeout;
  }
  if (text.contains('approval expired') ||
      text.contains('approval timed out') ||
      text.contains('receiver approval expired')) {
    return SendFailureReason.approvalExpired;
  }
  if (text.contains('certificate') ||
      text.contains('handshake') ||
      text.contains('fingerprint')) {
    return SendFailureReason.certificateMismatch;
  }
  if (text.contains('pin')) {
    return SendFailureReason.invalidPin;
  }
  if (text.contains('incompatible protocol') ||
      text.contains('update both devices') ||
      text.contains('protocol mismatch')) {
    return SendFailureReason.incompatibleVersion;
  }
  if (text.contains('checksum')) {
    return SendFailureReason.integrityCheckFailed;
  }
  if (text.contains('forbidden') ||
      text.contains('offer rejected') ||
      text.contains('declined')) {
    return SendFailureReason.rejected;
  }
  if (text.contains('transfer port unreachable') ||
      text.contains('could not reach transfer port')) {
    return SendFailureReason.transferUnreachable;
  }
  if (text.contains('file not found') || text.contains('missing source path')) {
    return SendFailureReason.missingLocalFile;
  }
  if (text.contains('socketexception') ||
      text.contains('connection refused') ||
      text.contains('failed host lookup') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable')) {
    return SendFailureReason.recipientOffline;
  }
  return SendFailureReason.unknown;
}
