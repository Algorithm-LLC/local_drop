import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class SafeArchiveExtractionResult {
  const SafeArchiveExtractionResult({required this.topLevelNames});

  final Set<String> topLevelNames;
}

class SafeArchiveException implements Exception {
  const SafeArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SafeArchiveExtractor {
  const SafeArchiveExtractor._();

  static const int defaultMaxExpandedBytes = 20 * 1024 * 1024 * 1024;

  static Future<SafeArchiveExtractionResult> extractZipToStaging({
    required File zipFile,
    required Directory stagingDirectory,
    int maxExpandedBytes = defaultMaxExpandedBytes,
  }) async {
    if (maxExpandedBytes <= 0) {
      throw const SafeArchiveException('Invalid archive size limit.');
    }
    final rootPath = p.normalize(stagingDirectory.absolute.path);
    final archive = ZipDecoder().decodeBytes(
      await zipFile.readAsBytes(),
      verify: true,
    );
    final seenOutputPaths = <String>{};
    final topLevelNames = <String>{};
    var expandedBytes = 0;

    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw const SafeArchiveException('Archive symlinks are not allowed.');
      }
      final safeRelativePath = validateArchiveRelativePath(entry.name);
      final firstSegment = safeRelativePath.split('/').first;
      topLevelNames.add(firstSegment);
      final outputPath = safeJoinWithin(
        rootPath: rootPath,
        relativePath: safeRelativePath,
      );
      if (!seenOutputPaths.add(p.normalize(outputPath))) {
        throw const SafeArchiveException('Archive contains duplicate entries.');
      }

      if (entry.isDirectory) {
        await Directory(outputPath).create(recursive: true);
        continue;
      }
      if (!entry.isFile) {
        throw const SafeArchiveException('Archive contains unsupported entry.');
      }

      expandedBytes += entry.size;
      if (expandedBytes > maxExpandedBytes) {
        throw const SafeArchiveException('Archive expands beyond the limit.');
      }

      await Directory(p.dirname(outputPath)).create(recursive: true);
      final output = OutputFileStream(outputPath);
      try {
        entry.writeContent(output, freeMemory: true);
      } finally {
        await output.close();
      }
    }

    if (topLevelNames.isEmpty) {
      throw const SafeArchiveException('Archive is empty.');
    }
    return SafeArchiveExtractionResult(topLevelNames: topLevelNames);
  }

  static String validateArchiveRelativePath(String rawPath) {
    if (rawPath.isEmpty || rawPath.contains('\\')) {
      throw const SafeArchiveException('Archive entry path is not safe.');
    }
    if (rawPath.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw const SafeArchiveException('Archive entry contains control chars.');
    }

    var normalized = rawPath.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw const SafeArchiveException('Archive entry path is not relative.');
    }

    final parts = normalized.split('/');
    for (final part in parts) {
      if (part.isEmpty ||
          part == '.' ||
          part == '..' ||
          RegExp(r'^[A-Za-z]:').hasMatch(part) ||
          part.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
        throw const SafeArchiveException('Archive entry path is not safe.');
      }
    }
    return parts.join('/');
  }

  static String safeJoinWithin({
    required String rootPath,
    required String relativePath,
  }) {
    final candidate = p.normalize(
      p.joinAll(<String>[rootPath, ...relativePath.split('/')]),
    );
    if (!p.isWithin(rootPath, candidate)) {
      throw const SafeArchiveException('Archive entry escapes destination.');
    }
    return candidate;
  }

  static String sanitizeDisplayName(String value, {String fallback = 'item'}) {
    var sanitized = value
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    while (sanitized.startsWith('.')) {
      sanitized = sanitized.substring(1).trimLeft();
    }
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      sanitized = fallback;
    }
    return sanitized;
  }
}
