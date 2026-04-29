import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_preferences.dart';
import '../../models/peer_presence_models.dart';
import '../../models/transfer_models.dart';

class AppStore {
  static const int schemaVersion = 1;

  static const String _preferencesKey = 'app_preferences';
  static const String _stateFileName = 'localdrop_state.json';
  static const MethodChannel _platformChannel = MethodChannel(
    'localdrop/network',
  );

  late SharedPreferences _prefs;
  late File _stateFile;
  Map<String, dynamic> _state = <String, dynamic>{
    'schemaVersion': schemaVersion,
  };

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final supportDir = await getApplicationSupportDirectory();
    final localDropDir = Directory(p.join(supportDir.path, 'LocalDrop'));
    if (!await localDropDir.exists()) {
      await localDropDir.create(recursive: true);
    }
    _stateFile = File(p.join(localDropDir.path, _stateFileName));
    if (await _stateFile.exists()) {
      final content = await _stateFile.readAsString();
      if (content.trim().isNotEmpty) {
        _state = jsonDecode(content) as Map<String, dynamic>;
      }
    }
    _state['schemaVersion'] =
        (_state['schemaVersion'] as num?)?.toInt() ?? schemaVersion;
    _state['history'] = (_state['history'] as List<dynamic>?) ?? <dynamic>[];
    _state['trustedPeers'] =
        (_state['trustedPeers'] as List<dynamic>?) ?? <dynamic>[];
    await _flushState();
  }

  Future<AppPreferences> loadPreferences() async {
    final raw = _prefs.getString(_preferencesKey);
    if (raw == null) {
      final defaults = AppPreferences(
        nickname: '',
        themePreference: AppThemePreference.system,
        saveDirectory: await resolveDefaultSaveDirectory(),
      );
      await savePreferences(defaults);
      return defaults;
    }
    final parsed = AppPreferences.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final resolvedDefaultSaveDirectory = await resolveDefaultSaveDirectory();
    final normalizedSaveDirectory = await _normalizeSavedDirectory(
      parsed.saveDirectory,
      resolvedDefaultSaveDirectory,
    );
    final normalizedPreferences = parsed.copyWith(
      saveDirectory: normalizedSaveDirectory,
    );
    if (normalizedSaveDirectory != parsed.saveDirectory) {
      await savePreferences(normalizedPreferences);
    }
    return parsed.copyWith(
      schemaVersion: schemaVersion,
      saveDirectory: normalizedSaveDirectory,
    );
  }

  Future<void> savePreferences(AppPreferences preferences) async {
    final encoded = jsonEncode(
      preferences.copyWith(schemaVersion: schemaVersion).toJson(),
    );
    await _prefs.setString(_preferencesKey, encoded);
  }

  List<TransferRecord> loadTransferHistory() {
    final entries = (_state['history'] as List<dynamic>?) ?? <dynamic>[];
    return entries
        .map((item) => TransferRecord.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> saveTransferHistory(List<TransferRecord> history) async {
    _state['history'] = history
        .map((item) => item.toJson())
        .toList(growable: false);
    await _flushState();
  }

  List<TrustedPeerRecord> loadTrustedPeers() {
    final entries = (_state['trustedPeers'] as List<dynamic>?) ?? <dynamic>[];
    return entries
        .whereType<Map<String, dynamic>>()
        .map(TrustedPeerRecord.fromJson)
        .where(
          (item) =>
              item.deviceId.trim().isNotEmpty &&
              item.certFingerprint.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<void> saveTrustedPeers(List<TrustedPeerRecord> peers) async {
    _state['trustedPeers'] = peers
        .map((item) => item.toJson())
        .toList(growable: false);
    await _flushState();
  }

  Future<String> resolveDefaultSaveDirectory() async {
    if (Platform.isIOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      if (!await documentsDir.exists()) {
        await documentsDir.create(recursive: true);
      }
      return documentsDir.path;
    }

    final candidateDirectories = <Directory>[
      if (await _resolveDownloadsDirectory() case final downloadsDir?)
        Directory(p.join(downloadsDir.path, 'LocalDrop')),
      Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'LocalDrop'),
      ),
      Directory(
        p.join((await getApplicationSupportDirectory()).path, 'LocalDrop'),
      ),
    ];

    for (final candidate in candidateDirectories) {
      if (await _ensureWritableDirectory(candidate)) {
        return candidate.path;
      }
    }

    throw const FileSystemException(
      'Could not prepare a writable LocalDrop save directory.',
    );
  }

  Future<Directory?> _resolveDownloadsDirectory() async {
    if (Platform.isAndroid || Platform.isMacOS) {
      try {
        final rawPath = await _platformChannel.invokeMethod<String>(
          'getPublicDownloadsDirectory',
        );
        final normalizedPath = rawPath?.trim() ?? '';
        if (normalizedPath.isNotEmpty) {
          return Directory(normalizedPath);
        }
      } catch (_) {
        // Fall back to path_provider below.
      }
    }
    return await getDownloadsDirectory();
  }

  Future<String> _normalizeSavedDirectory(
    String? currentPath,
    String resolvedDefaultPath,
  ) async {
    if (currentPath == null || currentPath.trim().isEmpty) {
      return resolvedDefaultPath;
    }
    if (Platform.isIOS) {
      final normalizedCurrent = p.normalize(currentPath);
      final normalizedDefault = p.normalize(resolvedDefaultPath);
      if (normalizedCurrent == normalizedDefault) {
        return normalizedCurrent;
      }

      final documentsParent = p.normalize(p.dirname(normalizedDefault));
      final nestedLegacyDefault = p.normalize(
        p.join(normalizedDefault, 'LocalDrop'),
      );
      if (normalizedCurrent == documentsParent ||
          normalizedCurrent == nestedLegacyDefault) {
        return normalizedDefault;
      }
      return normalizedCurrent;
    }

    if (Platform.isMacOS) {
      final normalizedCurrent = p.normalize(currentPath);
      final normalizedDefault = p.normalize(resolvedDefaultPath);
      if (normalizedCurrent == normalizedDefault) {
        return normalizedCurrent;
      }

      final documentsDefault = p.normalize(
        p.join((await getApplicationDocumentsDirectory()).path, 'LocalDrop'),
      );
      final supportDefault = p.normalize(
        p.join((await getApplicationSupportDirectory()).path, 'LocalDrop'),
      );
      final normalizedCurrentUnix = normalizedCurrent.replaceAll('\\', '/');
      final looksLikeLegacySandboxDownloadsDefault =
          p.basename(normalizedCurrent) == 'LocalDrop' &&
          normalizedCurrentUnix.contains('/Library/Containers/') &&
          normalizedCurrentUnix.contains('/Data/Downloads/');
      final looksLikePreviousAutoDefault =
          normalizedCurrent == documentsDefault ||
          normalizedCurrent == supportDefault;
      final restoredLegacyDownloadsPath = _restoreMacOSSandboxDownloadsPath(
        normalizedCurrent,
      );
      if (restoredLegacyDownloadsPath != null) {
        return restoredLegacyDownloadsPath;
      }
      if (looksLikeLegacySandboxDownloadsDefault ||
          looksLikePreviousAutoDefault) {
        return normalizedDefault;
      }
      return normalizedCurrent;
    }

    if (!Platform.isAndroid) {
      return currentPath;
    }
    final normalizedCurrent = p.normalize(currentPath);
    final normalizedDefault = p.normalize(resolvedDefaultPath);
    if (normalizedCurrent == normalizedDefault) {
      return normalizedCurrent;
    }

    final parentPath = p.dirname(normalizedCurrent).replaceAll('\\', '/');
    final looksLikeLegacyRootDefault =
        p.basename(normalizedCurrent) == 'LocalDrop' &&
        (parentPath == '/storage/emulated/0' ||
            parentPath == '/sdcard' ||
            parentPath == '/mnt/sdcard');
    if (looksLikeLegacyRootDefault) {
      return normalizedDefault;
    }
    return normalizedCurrent;
  }

  Future<bool> _ensureWritableDirectory(Directory directory) async {
    File? probeFile;
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      probeFile = File(p.join(directory.path, '.localdrop_write_probe'));
      await probeFile.writeAsString('ok', flush: true);
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
      return true;
    } catch (_) {
      if (probeFile != null) {
        try {
          if (await probeFile.exists()) {
            await probeFile.delete();
          }
        } catch (_) {
          // Ignore cleanup failures while probing writability.
        }
      }
      return false;
    }
  }

  String? _restoreMacOSSandboxDownloadsPath(String currentPath) {
    if (!Platform.isMacOS) {
      return null;
    }
    final normalized = p.normalize(currentPath).replaceAll('\\', '/');
    const containerMarker = '/Library/Containers/';
    const downloadsMarker = '/Data/Downloads/';
    final containerIndex = normalized.indexOf(containerMarker);
    final downloadsIndex = normalized.indexOf(downloadsMarker);
    if (containerIndex <= 0 || downloadsIndex <= containerIndex) {
      return null;
    }
    final userHome = normalized.substring(0, containerIndex);
    if (!userHome.startsWith('/Users/')) {
      return null;
    }
    final relativePath = normalized.substring(
      downloadsIndex + downloadsMarker.length,
    );
    if (relativePath.trim().isEmpty) {
      return null;
    }
    return p.normalize(p.join(userHome, 'Downloads', relativePath));
  }

  Future<void> _flushState() async {
    await _stateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_state),
      flush: true,
    );
  }
}
