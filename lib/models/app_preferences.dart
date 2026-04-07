import 'package:flutter/material.dart';

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
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final String nickname;
  final AppThemePreference themePreference;
  final String? saveDirectory;

  bool get needsOnboarding => nickname.trim().isEmpty;

  AppPreferences copyWith({
    int? schemaVersion,
    String? nickname,
    AppThemePreference? themePreference,
    String? saveDirectory,
    bool clearSaveDirectory = false,
  }) {
    return AppPreferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      nickname: nickname ?? this.nickname,
      themePreference: themePreference ?? this.themePreference,
      saveDirectory: clearSaveDirectory
          ? null
          : saveDirectory ?? this.saveDirectory,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'nickname': nickname,
      'themePreference': themePreference.name,
      'saveDirectory': saveDirectory,
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
    );
  }
}
