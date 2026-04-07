import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/transfer_models.dart';
import '../../services/platform_folder_opener.dart';

final PlatformFolderOpener _platformFolderOpener = PlatformFolderOpener();

String? transferFolderPathForRecord(TransferRecord record) {
  if (!record.isIncoming || record.status != TransferStatus.completed) {
    return null;
  }
  final sourcePaths = record.items
      .map((item) => item.sourcePath?.trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (sourcePaths.isEmpty) {
    return null;
  }

  if (sourcePaths.length == 1) {
    final sourcePath = sourcePaths.single;
    final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return sourcePath;
    }
    if (type == FileSystemEntityType.file) {
      return File(sourcePath).parent.path;
    }
    return p.dirname(sourcePath);
  }

  final directories = sourcePaths
      .map((sourcePath) {
        final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          return p.normalize(sourcePath);
        }
        if (type == FileSystemEntityType.file) {
          return p.normalize(File(sourcePath).parent.path);
        }
        return p.normalize(p.dirname(sourcePath));
      })
      .toList(growable: false);
  return _commonDirectory(directories) ?? directories.first;
}

List<String> transferSharePathsForRecord(TransferRecord record) {
  if (!record.isIncoming || record.status != TransferStatus.completed) {
    return const <String>[];
  }
  return record.items
      .map((item) => item.sourcePath?.trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _commonDirectory(List<String> directories) {
  if (directories.isEmpty) {
    return null;
  }
  var commonSegments = p.split(directories.first);
  for (final directory in directories.skip(1)) {
    final nextSegments = p.split(directory);
    final limit = commonSegments.length < nextSegments.length
        ? commonSegments.length
        : nextSegments.length;
    var matched = 0;
    while (matched < limit &&
        commonSegments[matched] == nextSegments[matched]) {
      matched += 1;
    }
    commonSegments = commonSegments.take(matched).toList(growable: false);
    if (commonSegments.isEmpty) {
      return null;
    }
  }
  return p.joinAll(commonSegments);
}

Future<void> openTransferFolder(
  BuildContext context, {
  required String folderPath,
  required String title,
  List<String> sharePaths = const <String>[],
}) async {
  final navigator = Navigator.of(context);
  if (Platform.isIOS && sharePaths.isNotEmpty) {
    final shareResult = await _platformFolderOpener.shareItems(sharePaths);
    if (shareResult.openedNatively) {
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => TransferFolderPage(
          folderPath: folderPath,
          title: title,
        ),
      ),
    );
    return;
  }
  final result = await _platformFolderOpener.openFolder(folderPath);
  if (result.openedNatively) {
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => TransferFolderPage(
        folderPath: folderPath,
        title: title,
      ),
    ),
  );
}

class TransferFolderPage extends StatefulWidget {
  const TransferFolderPage({
    super.key,
    required this.folderPath,
    required this.title,
  });

  final String folderPath;
  final String title;

  @override
  State<TransferFolderPage> createState() => _TransferFolderPageState();
}

class _TransferFolderPageState extends State<TransferFolderPage> {
  late final Future<List<_FolderEntry>> _entriesFuture = _loadEntries();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<_FolderEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FolderInfo(
              title: l10n.transferFolderUnavailable,
              subtitle: widget.folderPath,
              icon: Icons.folder_off,
            );
          }

          final entries = snapshot.data ?? const <_FolderEntry>[];
          if (entries.isEmpty) {
            return _FolderInfo(
              title: l10n.transferFolderEmpty,
              subtitle: widget.folderPath,
              icon: Icons.folder_open,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.transferFolderPathLabel,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(widget.folderPath),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder
                              : Icons.insert_drive_file,
                        ),
                        title: Text(entry.name),
                        subtitle: entry.subtitle == null
                            ? null
                            : Text(entry.subtitle!),
                        onTap: entry.isDirectory
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TransferFolderPage(
                                      folderPath: entry.path,
                                      title: entry.name,
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<_FolderEntry>> _loadEntries() async {
    final directory = Directory(widget.folderPath);
    if (!await directory.exists()) {
      throw StateError('Folder not found');
    }

    final entries = <_FolderEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final stat = await entity.stat();
      entries.add(
        _FolderEntry(
          path: entity.path,
          name: p.basename(entity.path),
          isDirectory: stat.type == FileSystemEntityType.directory,
          subtitle: stat.type == FileSystemEntityType.file
              ? _formatBytes(stat.size)
              : null,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _FolderInfo extends StatelessWidget {
  const _FolderInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _FolderEntry {
  const _FolderEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.subtitle,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final String? subtitle;
}
