import 'dart:io';

import 'package:flutter/services.dart';

typedef FolderProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });
typedef FolderPlatformInvoker =
    Future<dynamic> Function(String method, [dynamic arguments]);

enum OpenFolderResultKind { openedNatively, unsupported, failed }

class OpenFolderResult {
  const OpenFolderResult._({required this.kind, this.message});

  const OpenFolderResult.openedNatively()
    : this._(kind: OpenFolderResultKind.openedNatively);

  const OpenFolderResult.unsupported()
    : this._(kind: OpenFolderResultKind.unsupported);

  const OpenFolderResult.failed([String? message])
    : this._(kind: OpenFolderResultKind.failed, message: message);

  final OpenFolderResultKind kind;
  final String? message;

  bool get openedNatively => kind == OpenFolderResultKind.openedNatively;
}

class PlatformFolderOpener {
  PlatformFolderOpener({
    FolderProcessStarter? processStarter,
    FolderPlatformInvoker? platformInvoker,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
    bool? isAndroid,
    bool? isIOS,
  }) : _processStarter = processStarter ?? Process.start,
       _platformInvoker = platformInvoker ?? _defaultPlatformInvoker,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS;

  static const MethodChannel _platformChannel = MethodChannel(
    'localdrop/network',
  );

  final FolderProcessStarter _processStarter;
  final FolderPlatformInvoker _platformInvoker;
  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;
  final bool _isAndroid;
  final bool _isIOS;

  static Future<dynamic> _defaultPlatformInvoker(
    String method, [
    dynamic arguments,
  ]) {
    return _platformChannel.invokeMethod<dynamic>(method, arguments);
  }

  Future<OpenFolderResult> openFolder(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return const OpenFolderResult.failed('Folder path is empty.');
    }

    final entityType = FileSystemEntity.typeSync(
      normalizedPath,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.notFound) {
      return const OpenFolderResult.failed('Folder path does not exist.');
    }

    final targetDirectory = entityType == FileSystemEntityType.file
        ? File(normalizedPath).parent.path
        : normalizedPath;

    try {
      if (_isWindows) {
        await _processStarter('explorer.exe', <String>[targetDirectory]);
        return const OpenFolderResult.openedNatively();
      }
      if (_isMacOS) {
        await _processStarter('open', <String>[targetDirectory]);
        return const OpenFolderResult.openedNatively();
      }
      if (_isLinux) {
        await _processStarter('xdg-open', <String>[targetDirectory]);
        return const OpenFolderResult.openedNatively();
      }
      if (_isAndroid) {
        final opened = await _platformInvoker('openFolder', <String, dynamic>{
          'path': targetDirectory,
        });
        if (opened == true) {
          return const OpenFolderResult.openedNatively();
        }
        return const OpenFolderResult.failed(
          'Android could not open the folder in a file manager.',
        );
      }
      if (_isIOS) {
        final opened = await _platformInvoker('openFolder', <String, dynamic>{
          'path': targetDirectory,
        });
        if (opened == true) {
          return const OpenFolderResult.openedNatively();
        }
        return const OpenFolderResult.failed(
          'iPhone could not open the share sheet.',
        );
      }
      return const OpenFolderResult.unsupported();
    } on PlatformException catch (error) {
      return OpenFolderResult.failed(error.message ?? error.code);
    } catch (error) {
      return OpenFolderResult.failed(error.toString());
    }
  }

  Future<OpenFolderResult> shareItems(List<String> paths) async {
    final normalizedPaths = paths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where(
          (item) =>
              FileSystemEntity.typeSync(item, followLinks: false) !=
              FileSystemEntityType.notFound,
        )
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return const OpenFolderResult.failed('No files are available to share.');
    }
    if (!_isIOS) {
      return const OpenFolderResult.unsupported();
    }

    try {
      final opened = await _platformInvoker('sharePaths', <String, dynamic>{
        'paths': normalizedPaths,
      });
      if (opened == true) {
        return const OpenFolderResult.openedNatively();
      }
      return const OpenFolderResult.failed(
        'iPhone could not open the share sheet.',
      );
    } on PlatformException catch (error) {
      return OpenFolderResult.failed(error.message ?? error.code);
    } catch (error) {
      return OpenFolderResult.failed(error.toString());
    }
  }
}
