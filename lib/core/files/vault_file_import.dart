import 'dart:io';

import '../crypto/crypto.dart';

enum FileImportProblem { limit, name, notFile, changed }

class FileImportException implements Exception {
  final FileImportProblem problem;

  const FileImportException(this.problem);
}

Future<List<VaultEntry>> readVaultFiles(
  VaultSession session,
  List<String> paths, {
  String? folderId,
}) async {
  final unique = <String, File>{};
  for (final path in paths) {
    final file = File(path).absolute;
    unique.putIfAbsent(file.path.toLowerCase(), () => file);
  }
  if (session.entries.where((e) => e.isFile).length + unique.length > VaultCipher.maxFiles) {
    throw const FileImportException(FileImportProblem.limit);
  }
  var total = session.entries.expand((e) => e.attachments).fold<int>(0, (sum, a) => sum + a.size);
  final entries = <VaultEntry>[];
  for (final file in unique.values) {
    if (session.isLocked) throw StateError('Vault is locked');
    if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file) {
      throw const FileImportException(FileImportProblem.notFile);
    }
    final name = file.uri.pathSegments.last;
    if (!VaultAttachment.validName(name)) {
      throw const FileImportException(FileImportProblem.name);
    }
    final handle = await file.open();
    try {
      final size = await handle.length();
      if (size > VaultCipher.maxAttachmentBytes || total + size > VaultCipher.maxTotalAttachmentBytes) {
        throw const FileImportException(FileImportProblem.limit);
      }
      final bytes = await handle.read(size + 1);
      try {
        if (bytes.length != size || await handle.length() != size) {
          throw const FileImportException(FileImportProblem.changed);
        }
        if (session.isLocked) throw StateError('Vault is locked');
        entries.add(
          VaultEntry.file(
            VaultAttachment.create(name, bytes),
            folderId: folderId,
          ),
        );
        total += bytes.length;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } finally {
      await handle.close();
    }
  }
  return entries;
}
