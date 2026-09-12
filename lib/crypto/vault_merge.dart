import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'cancellable_worker.dart';
import 'vault_cipher.dart';

class VaultMerge {
  final List<VaultEntry> entries;
  final List<VaultFolder> folders;
  final String? name;
  final int conflicts;

  VaultMerge(
    this.entries,
    this.folders,
    this.name,
    this.conflicts,
  );

  static Future<VaultMerge> combine(
    VaultSession base,
    VaultSession local,
    VaultSession remote,
  ) {
    final sameKey = local.hasSameKeyEnvelope(remote) && local.hasSameKeyEnvelope(base);
    if (sameKey == false) throw const VaultUnlockException();
    return local.runWorker(
      _startMerge(
        _MergeInput(base.entries, base.folders, base.name),
        _MergeInput(local.entries, local.folders, local.name),
        _MergeInput(remote.entries, remote.folders, remote.name),
      ),
    );
  }

  static Future<VaultMerge> _combine(
    _MergeInput base,
    _MergeInput local,
    _MergeInput remote,
  ) async {
    var conflicts = 0;
    final localFolderIds = <String, String>{};
    final localFolders = <String>{};
    final folders = <String, Map<String, dynamic>>{};
    final baseFolders = {for (final f in base.folders) f.id: f.toJson()};
    final localFolderVersions = {for (final f in local.folders) f.id: f.toJson()};
    final remoteFolders = {for (final f in remote.folders) f.id: f.toJson()};
    for (final id in {...baseFolders.keys, ...localFolderVersions.keys, ...remoteFolders.keys}.toList()..sort()) {
      final baseFolder = baseFolders[id];
      final localFolder = localFolderVersions[id];
      final remoteFolder = remoteFolders[id];
      _alignOrder(baseFolder, localFolder, remoteFolder, 'parentId');
      Map<String, dynamic>? selected;
      if (_equal(localFolder, remoteFolder) || _equal(remoteFolder, baseFolder)) {
        selected = localFolder;
        localFolders.add(id);
      } else if (_equal(localFolder, baseFolder)) {
        selected = remoteFolder;
      } else {
        conflicts++;
        selected = remoteFolder ?? localFolder;
        if (remoteFolder == null) localFolders.add(id);
        if (localFolder != null && remoteFolder != null) {
          final fork = await _forkId('folder', localFolder);
          if (baseFolders.containsKey(fork) ||
              localFolderVersions.containsKey(fork) ||
              remoteFolders.containsKey(fork)) {
            if (!_equal({
              ...localFolder,
              'id': fork,
            }, localFolderVersions[fork] ?? remoteFolders[fork] ?? baseFolders[fork])) {
              throw const VaultFormatException();
            }
          }
          localFolderIds[id] = fork;
          folders[fork] = {...localFolder, 'id': fork};
          localFolders.add(fork);
        }
      }
      if (selected != null) folders[id] = selected;
    }
    for (final id in localFolders) {
      final folder = folders[id];
      if (folder == null) continue;
      folder['parentId'] = localFolderIds[folder['parentId']] ?? folder['parentId'];
    }
    for (final folder in folders.values.toList()) {
      final parentId = folder['parentId'] as String?;
      if (parentId == null || folders.containsKey(parentId)) continue;
      final parent = remoteFolders[parentId] ?? localFolderVersions[parentId] ?? baseFolders[parentId];
      if (parent == null || parent['parentId'] != null) throw const VaultFormatException();
      folders[parentId] = parent;
    }

    final baseEntries = {for (final e in base.entries) e.id: e};
    final localEntries = {for (final e in local.entries) e.id: e};
    final remoteEntries = {for (final e in remote.entries) e.id: e};
    final entries = <String, VaultEntry>{};
    Map<String, dynamic> withLocalFolder(Map<String, dynamic> e) => {
      ...e,
      'folderId': localFolderIds[e['folderId']] ?? e['folderId'],
    };
    for (final id in {...baseEntries.keys, ...localEntries.keys, ...remoteEntries.keys}.toList()..sort()) {
      final baseEntry = baseEntries[id]?.toJson();
      final localEntry = localEntries[id]?.toJson();
      final remoteEntry = remoteEntries[id]?.toJson();
      _alignOrder(baseEntry, localEntry, remoteEntry, 'folderId');
      Map<String, dynamic>? selected;
      if (_equal(localEntry, remoteEntry) || _equal(remoteEntry, baseEntry)) {
        selected = localEntry == null ? null : withLocalFolder(localEntry);
      } else if (_equal(localEntry, baseEntry)) {
        selected = remoteEntry;
      } else {
        conflicts++;
        selected = remoteEntry ?? (localEntry == null ? null : withLocalFolder(localEntry));
        if (selected != null) selected = {...selected, 'conflictOf': id};
        if (localEntry != null && remoteEntry != null) {
          final fork = await _forkId('entry', {...localEntry, 'conflictOf': null});
          final copy = {...withLocalFolder(localEntry), 'id': fork, 'conflictOf': id};
          copy['attachments'] = [
            for (final a in localEntry['attachments'] as List)
              {
                ...a as Map<String, dynamic>,
                'id': await _forkId('attachment/$fork', a),
              },
          ];
          final existing = (localEntries[fork] ?? remoteEntries[fork] ?? baseEntries[fork])?.toJson();
          if (existing != null && !_equal(existing, copy)) {
            throw const VaultFormatException();
          }
          entries[fork] = VaultEntry.fromJson(copy);
        }
      }
      if (selected != null) {
        entries[id] = VaultEntry.fromJson(selected);
      }
    }
    var name = remote.name;
    if (local.name == remote.name || remote.name == base.name) {
      name = local.name;
    } else if (local.name != base.name) {
      final names = {
        ...?remote.name?.split(' / '),
        ...?local.name?.split(' / '),
      }.toList()..sort();
      final combined = names.join(' / ');
      if (combined.length > 120) throw const VaultFormatException();
      name = combined;
      conflicts++;
    }
    return VaultMerge(
      [
        for (final e in entries.values) e.inFolder(folders.containsKey(e.folderId) ? e.folderId : null),
      ],
      folders.values.map(VaultFolder.fromJson).toList(),
      name,
      conflicts,
    );
  }

  static Future<bool> sameContents(VaultMerge merged, VaultSession session) => session.runWorker(
    _startCompare(
      merged,
      _MergeInput(session.entries, session.folders, session.name),
    ),
  );

  static bool _sameContents(VaultMerge merged, _MergeInput session) {
    if (merged.name != session.name ||
        merged.entries.length != session.entries.length ||
        merged.folders.length != session.folders.length) {
      return false;
    }
    final entries = {for (final e in session.entries) e.id: e};
    for (final e in merged.entries) {
      if (!_equal(e.toJson(), entries[e.id]?.toJson())) return false;
    }
    final folders = {for (final f in session.folders) f.id: f};
    return merged.folders.every(
      (f) => _equal(f.toJson(), folders[f.id]?.toJson()),
    );
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static void _alignOrder(
    Map<String, dynamic>? base,
    Map<String, dynamic>? local,
    Map<String, dynamic>? remote,
    String parentKey,
  ) {
    if (base == null || local == null || remote == null) return;
    if (base[parentKey] != local[parentKey] || base[parentKey] != remote[parentKey]) return;
    final b = base['order'] as int;
    final l = local['order'] as int;
    final r = remote['order'] as int;
    final int order;
    if (l == b) {
      order = r;
    } else if (r == b || l == r) {
      order = l;
    } else {
      order = l < r ? l : r;
    }
    base['order'] = order;
    local['order'] = order;
    remote['order'] = order;
  }

  static bool _equal(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static Future<String> _forkId(String kind, Object value) async {
    final bytes = utf8.encode('$kind/${jsonEncode(_canonical(value))}');
    try {
      final digest = await Sha256().hash(bytes);
      return 'sync:${base64UrlEncode(digest.bytes)}';
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

class _MergeInput {
  final List<VaultEntry> entries;
  final List<VaultFolder> folders;
  final String? name;

  _MergeInput(
    this.entries,
    this.folders,
    this.name,
  );
}

CancellableWorker<VaultMerge> _startMerge(
  _MergeInput base,
  _MergeInput local,
  _MergeInput remote,
) => CancellableWorker(() => VaultMerge._combine(base, local, remote));
CancellableWorker<bool> _startCompare(VaultMerge merged, _MergeInput session) =>
    CancellableWorker(() async => VaultMerge._sameContents(merged, session));
