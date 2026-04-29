import 'package:flutter/material.dart';

import '../services/transfer_pin_service.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  ThemeMode get toThemeMode {
    switch (this) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  static AppThemePreference fromStorage(String value) {
    return AppThemePreference.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppThemePreference.system,
    );
  }
}

class AppPreferences {
  const AppPreferences({
    required this.nickname,
    required this.themePreference,
    required this.saveDirectory,
    this.transferPinAlgorithm,
    this.transferPinSaltBase64,
    this.transferPinHashBase64,
    this.transferPinIterations = 0,
    this.transferPinPolicyVersion = 0,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final String nickname;
  final AppThemePreference themePreference;
  final String? saveDirectory;
  final String? transferPinAlgorithm;
  final String? transferPinSaltBase64;
  final String? transferPinHashBase64;
  final int transferPinIterations;
  final int transferPinPolicyVersion;

  bool get hasTransferPin =>
      (transferPinAlgorithm?.trim().isNotEmpty ?? false) &&
      (transferPinSaltBase64?.trim().isNotEmpty ?? false) &&
      (transferPinHashBase64?.trim().isNotEmpty ?? false) &&
      transferPinIterations > 0;

  bool get hasCurrentTransferPin =>
      hasTransferPin &&
      transferPinPolicyVersion >= TransferPinService.currentPolicyVersion;

  bool get needsOnboarding => nickname.trim().isEmpty || !hasCurrentTransferPin;

  AppPreferences copyWith({
    int? schemaVersion,
    String? nickname,
    AppThemePreference? themePreference,
    String? saveDirectory,
    Object? transferPinAlgorithm = _sentinel,
    Object? transferPinSaltBase64 = _sentinel,
    Object? transferPinHashBase64 = _sentinel,
    int? transferPinIterations,
    int? transferPinPolicyVersion,
    bool clearSaveDirectory = false,
  }) {
    return AppPreferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      nickname: nickname ?? this.nickname,
      themePreference: themePreference ?? this.themePreference,
      saveDirectory: clearSaveDirectory
          ? null
          : saveDirectory ?? this.saveDirectory,
      transferPinAlgorithm: identical(transferPinAlgorithm, _sentinel)
          ? this.transferPinAlgorithm
          : transferPinAlgorithm as String?,
      transferPinSaltBase64: identical(transferPinSaltBase64, _sentinel)
          ? this.transferPinSaltBase64
          : transferPinSaltBase64 as String?,
      transferPinHashBase64: identical(transferPinHashBase64, _sentinel)
          ? this.transferPinHashBase64
          : transferPinHashBase64 as String?,
      transferPinIterations:
          transferPinIterations ?? this.transferPinIterations,
      transferPinPolicyVersion:
          transferPinPolicyVersion ?? this.transferPinPolicyVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'nickname': nickname,
      'themePreference': themePreference.name,
      'saveDirectory': saveDirectory,
      'transferPinAlgorithm': transferPinAlgorithm,
      'transferPinSaltBase64': transferPinSaltBase64,
      'transferPinHashBase64': transferPinHashBase64,
      'transferPinIterations': transferPinIterations,
      'transferPinPolicyVersion': transferPinPolicyVersion,
    };
  }

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    return AppPreferences(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      nickname: (json['nickname'] as String?) ?? '',
      themePreference: AppThemePreference.fromStorage(
        (json['themePreference'] as String?) ?? AppThemePreference.system.name,
      ),
      saveDirectory: json['saveDirectory'] as String?,
      transferPinAlgorithm: json['transferPinAlgorithm'] as String?,
      transferPinSaltBase64: json['transferPinSaltBase64'] as String?,
      transferPinHashBase64: json['transferPinHashBase64'] as String?,
      transferPinIterations:
          (json['transferPinIterations'] as num?)?.toInt() ?? 0,
      transferPinPolicyVersion:
          (json['transferPinPolicyVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

const Object _sentinel = Object();
