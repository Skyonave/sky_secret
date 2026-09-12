import 'dart:io';
import 'dart:math';

import 'vault_store.dart';

class VaultReference {
  final String id;
  final File file;

  const VaultReference({required this.id, required this.file});

  VaultStore get store => VaultStore(file: file);
}

class VaultCatalog {
  final Directory directory;

  VaultCatalog({required this.directory});

  factory VaultCatalog.local() => VaultCatalog(directory: VaultStore.local().file.parent);

  VaultReference get legacy => VaultReference(
    id: 'legacy',
    file: File('${directory.path}${Platform.pathSeparator}vault.smv'),
  );

  Future<List<VaultReference>> list() async {
    final result = <VaultReference>[];
    if (await legacy.store.exists()) result.add(legacy);
    final folder = Directory(
      '${directory.path}${Platform.pathSeparator}vaults',
    );
    final type = await FileSystemEntity.type(folder.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return result;
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('Vault directory is unavailable');
    }
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!RegExp(r'^[0-9a-f]{32}\.smv$').hasMatch(name)) continue;
      result.add(VaultReference(id: name.substring(0, 32), file: entity));
    }
    result.sort(
      (a, b) => a.id == b.id
          ? 0
          : a.id == 'legacy'
          ? -1
          : b.id == 'legacy'
          ? 1
          : a.id.compareTo(b.id),
    );
    return result;
  }

  Future<List<({VaultReference vault, File file, DateTime date})>> history() async {
    final references = <VaultReference>[legacy];
    final folder = Directory('${directory.path}/vaults');
    if (await FileSystemEntity.type(folder.path, followLinks: false) == FileSystemEntityType.directory) {
      await for (final entity in folder.list(followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entity is Directory && RegExp(r'^[0-9a-f]{32}\.smv\.history$').hasMatch(name)) {
          references.add(
            VaultReference(
              id: name.substring(0, 32),
              file: File('${folder.path}/${name.substring(0, 36)}'),
            ),
          );
        }
      }
    }
    final result = <({VaultReference vault, File file, DateTime date})>[];
    for (final reference in references) {
      for (final file in await reference.store.history()) {
        result.add((
          vault: reference,
          file: file,
          date: await file.lastModified(),
        ));
      }
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  VaultReference newVault() {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return VaultReference(
      id: id,
      file: File(
        '${directory.path}${Platform.pathSeparator}vaults${Platform.pathSeparator}$id.smv',
      ),
    );
  }
}
