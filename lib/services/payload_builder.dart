import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/transfer_models.dart';
import 'media_selection_service.dart';

class PayloadBuilder {
  PayloadBuilder({MediaSelectionService? mediaSelectionService})
    : _mediaSelectionService = mediaSelectionService ?? MediaSelectionService();

  final Uuid _uuid = const Uuid();
  final MediaSelectionService _mediaSelectionService;

  Future<List<TransferItem>> pickByType(TransferPayloadType type) async {
    switch (type) {
      case TransferPayloadType.file:
        return _pickFileItems(FileType.any);
      case TransferPayloadType.photo:
        if (_mediaSelectionService.shouldUseSystemPicker) {
          return _pickSystemMediaItems(
            type: TransferPayloadType.photo,
            pathsLoader: _mediaSelectionService.pickPhotos,
          );
        }
        return _pickFileItems(
          FileType.custom,
          allowedExtensions: const <String>[
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'heic',
          ],
          forceType: TransferPayloadType.photo,
        );
      case TransferPayloadType.video:
        if (_mediaSelectionService.shouldUseSystemPicker) {
          return _pickSystemMediaItems(
            type: TransferPayloadType.video,
            pathsLoader: _mediaSelectionService.pickVideos,
          );
        }
        return _pickFileItems(
          FileType.custom,
          allowedExtensions: const <String>['mp4', 'mov', 'avi', 'mkv', 'webm'],
          forceType: TransferPayloadType.video,
        );
      case TransferPayloadType.folder:
        final item = await _pickFolderAsArchive();
        return item == null ? const <TransferItem>[] : <TransferItem>[item];
      case TransferPayloadType.text:
      case TransferPayloadType.clipboard:
        return const <TransferItem>[];
    }
  }

  Future<List<TransferItem>> _pickSystemMediaItems({
    required TransferPayloadType type,
    required Future<List<String>> Function() pathsLoader,
  }) async {
    final paths = await pathsLoader();
    if (paths.isEmpty) {
      return const <TransferItem>[];
    }

    final items = <TransferItem>[];
    for (final path in paths) {
      final item = await _buildFileItem(path, forceType: type);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  Future<List<TransferItem>> fromPaths(List<String> paths) async {
    if (paths.isEmpty) {
      return const <TransferItem>[];
    }

    final items = <TransferItem>[];
    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty) {
        continue;
      }
      final entityType = await FileSystemEntity.type(path);
      if (entityType == FileSystemEntityType.directory) {
        final item = await _archiveDirectory(path);
        if (item != null) {
          items.add(item);
        }
        continue;
      }
      if (entityType == FileSystemEntityType.file) {
        final fileType = _inferTypeFromPath(path);
        final item = await _buildFileItem(path, forceType: fileType);
        if (item != null) {
          items.add(item);
        }
      }
    }
    return items;
  }

  Future<TransferItem?> fromText({
    required String text,
    required TransferPayloadType type,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final bytes = utf8.encode(trimmed);
    return TransferItem(
      id: _uuid.v4(),
      type: type,
      name: type == TransferPayloadType.clipboard
          ? 'clipboard.txt'
          : 'note.txt',
      sizeBytes: bytes.length,
      checksumSha256: sha256.convert(bytes).toString().toUpperCase(),
      textContent: trimmed,
    );
  }

  Future<TransferItem?> fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    return fromText(text: text, type: TransferPayloadType.clipboard);
  }

  Future<List<TransferItem>> _pickFileItems(
    FileType pickerType, {
    List<String>? allowedExtensions,
    TransferPayloadType? forceType,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: pickerType,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    if (result == null) {
      return const <TransferItem>[];
    }

    final items = <TransferItem>[];
    for (final selected in result.files) {
      final path = selected.path;
      if (path == null) {
        continue;
      }
      final item = await _buildFileItem(path, forceType: forceType);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  Future<TransferItem?> _pickFolderAsArchive() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return null;
    }
    final folder = Directory(directoryPath);
    if (!await folder.exists()) {
      return null;
    }
    return _archiveDirectory(directoryPath);
  }

  Future<TransferItem?> _buildFileItem(
    String path, {
    TransferPayloadType? forceType,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final checksum = await _sha256File(file);
    return TransferItem(
      id: _uuid.v4(),
      type: forceType ?? _inferTypeFromPath(path),
      name: p.basename(path),
      sizeBytes: await file.length(),
      checksumSha256: checksum,
      sourcePath: path,
    );
  }

  Future<TransferItem?> _archiveDirectory(String directoryPath) async {
    final folder = Directory(directoryPath);
    if (!await folder.exists()) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final archive = Archive();
    final rootName = p.basename(directoryPath);
    final zipName = '$rootName.zip';
    final tempZipName =
        '${rootName}_${DateTime.now().millisecondsSinceEpoch}.zip';
    final zipPath = p.join(tempDir.path, tempZipName);
    archive.add(ArchiveFile.directory(rootName));

    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: directoryPath);
      if (relativePath == '.' || relativePath.trim().isEmpty) {
        continue;
      }
      final archivePath = p.join(rootName, relativePath).replaceAll('\\', '/');
      if (entity is Directory) {
        archive.add(ArchiveFile.directory(archivePath));
        continue;
      }
      if (entity is! File) {
        continue;
      }
      final bytes = await entity.readAsBytes();
      archive.add(ArchiveFile(archivePath, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      return null;
    }

    final archiveFile = File(zipPath);
    await archiveFile.writeAsBytes(encoded, flush: true);
    final checksum = await _sha256File(archiveFile);
    return TransferItem(
      id: _uuid.v4(),
      type: TransferPayloadType.folder,
      name: zipName,
      sizeBytes: await archiveFile.length(),
      checksumSha256: checksum,
      sourcePath: archiveFile.path,
    );
  }

  TransferPayloadType _inferTypeFromPath(String path) {
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    const photoExtensions = <String>{
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'heic',
    };
    const videoExtensions = <String>{'mp4', 'mov', 'avi', 'mkv', 'webm'};
    if (photoExtensions.contains(extension)) {
      return TransferPayloadType.photo;
    }
    if (videoExtensions.contains(extension)) {
      return TransferPayloadType.video;
    }
    return TransferPayloadType.file;
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toUpperCase();
  }
}
