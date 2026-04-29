import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_drop/services/safe_archive_extractor.dart';
import 'package:path/path.dart' as p;

void main() {
  test('extracts a valid folder zip into staging', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localdrop_zip_valid_',
    );
    try {
      final zip = await _writeZip(tempDir, <ArchiveFile>[
        ArchiveFile.string('Folder/hello.txt', 'hello'),
        ArchiveFile.string('Folder/nested/world.txt', 'world'),
      ]);
      final staging = Directory(p.join(tempDir.path, 'staging'))..createSync();

      final result = await SafeArchiveExtractor.extractZipToStaging(
        zipFile: zip,
        stagingDirectory: staging,
      );

      expect(result.topLevelNames, <String>{'Folder'});
      expect(
        await File(p.join(staging.path, 'Folder', 'hello.txt')).readAsString(),
        'hello',
      );
      expect(
        await File(
          p.join(staging.path, 'Folder', 'nested', 'world.txt'),
        ).readAsString(),
        'world',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects unsafe archive paths', () async {
    final unsafeNames = <String>[
      '../escape.txt',
      '/tmp/escape.txt',
      'C:/Temp/escape.txt',
      r'C:\Temp\escape.txt',
      r'Folder\..\escape.txt',
      'Folder/../escape.txt',
      'Folder/\u0001.txt',
      '',
    ];

    for (final unsafeName in unsafeNames) {
      expect(
        () => SafeArchiveExtractor.validateArchiveRelativePath(unsafeName),
        throwsA(isA<SafeArchiveException>()),
        reason: unsafeName,
      );
    }
  });

  test('rejects duplicate entries and oversized expansion', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localdrop_zip_reject_',
    );
    try {
      final duplicateZip = await _writeZip(tempDir, <ArchiveFile>[
        ArchiveFile.directory('Folder/a.txt/'),
        ArchiveFile.string('Folder/a.txt', 'one'),
      ], name: 'duplicate.zip');
      await expectLater(
        SafeArchiveExtractor.extractZipToStaging(
          zipFile: duplicateZip,
          stagingDirectory: Directory(p.join(tempDir.path, 'dup'))
            ..createSync(),
        ),
        throwsA(isA<SafeArchiveException>()),
      );

      final oversizedZip = await _writeZip(tempDir, <ArchiveFile>[
        ArchiveFile.string('Folder/big.txt', 'too big'),
      ], name: 'oversized.zip');
      await expectLater(
        SafeArchiveExtractor.extractZipToStaging(
          zipFile: oversizedZip,
          stagingDirectory: Directory(p.join(tempDir.path, 'oversized'))
            ..createSync(),
          maxExpandedBytes: 2,
        ),
        throwsA(isA<SafeArchiveException>()),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

Future<File> _writeZip(
  Directory directory,
  List<ArchiveFile> files, {
  String name = 'archive.zip',
}) async {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  final bytes = ZipEncoder().encode(archive);
  final zip = File(p.join(directory.path, name));
  await zip.writeAsBytes(bytes);
  return zip;
}
