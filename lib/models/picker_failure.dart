import 'dart:io';

import 'package:flutter/services.dart';

enum PickerFailureReason { unavailable, failedToOpen }

class PickerFailure implements Exception {
  const PickerFailure({
    required this.reason,
    required this.operation,
    required this.platform,
    this.code,
    this.details,
  });

  factory PickerFailure.fromPlatformException({
    required String operation,
    required PlatformException error,
  }) {
    final code = error.code.trim();
    final details = <String>[
      if ((error.message ?? '').trim().isNotEmpty) error.message!.trim(),
      if (error.details != null) error.details.toString().trim(),
    ].where((item) => item.isNotEmpty).join(' | ');
    final normalized = '$code $details'.toLowerCase();
    final isEntitlementIssue =
        code.startsWith('ENTITLEMENT_') || normalized.contains('entitlement');
    return PickerFailure(
      reason: isEntitlementIssue
          ? PickerFailureReason.unavailable
          : PickerFailureReason.failedToOpen,
      operation: operation,
      platform: Platform.operatingSystem,
      code: code.isEmpty ? null : code,
      details: details.isEmpty ? null : details,
    );
  }

  factory PickerFailure.fromError({
    required String operation,
    required Object error,
  }) {
    final details = error.toString().trim();
    return PickerFailure(
      reason: PickerFailureReason.failedToOpen,
      operation: operation,
      platform: Platform.operatingSystem,
      details: details.isEmpty ? null : details,
    );
  }

  final PickerFailureReason reason;
  final String operation;
  final String platform;
  final String? code;
  final String? details;

  bool get isMacOSAvailabilityIssue =>
      platform.toLowerCase() == 'macos' &&
      reason == PickerFailureReason.unavailable;

  Map<String, Object?> toLogData() {
    return <String, Object?>{
      'operation': operation,
      'platform': platform,
      'reason': reason.name,
      'code': code,
      'details': details,
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer('PickerFailure($operation, ${reason.name}');
    if (code != null) {
      buffer.write(', code: $code');
    }
    if (details != null) {
      buffer.write(', details: $details');
    }
    buffer.write(')');
    return buffer.toString();
  }
}
