import 'dart:typed_data';

import '../../../core/sync/github/github_api.dart';
import '../../../core/sync/github/github_backup.dart';
import 'vault_session_controller.dart';

enum VaultSyncResult { unavailable, done, keyChanged, rollback, failed, cleanupPending, conflicts }

class VaultSyncController {
  final VaultSessionController vault;
  bool _busy = false;

  VaultSyncController(this.vault);

  bool get busy => _busy;

  Future<VaultSyncResult> synchronize(GitHubBackup backup) async {
    final session = vault.session;
    final store = vault.store;
    final id = vault.selectedId;
    if (_busy || backup.busy || session == null || store == null || id == null || vault.owns(session) == false) {
      return VaultSyncResult.unavailable;
    }
    _busy = true;
    try {
      await backup.synchronizeVault(id, store, session);
      if (vault.owns(session) == false) return VaultSyncResult.unavailable;
      vault.rememberName();
      if (backup.syncKeyChanged) return VaultSyncResult.keyChanged;
      if (backup.syncRollback) return VaultSyncResult.rollback;
      if (backup.problem != null) return VaultSyncResult.failed;
      if (store.snapshotCleanupPending) return VaultSyncResult.cleanupPending;
      if (backup.mergedConflicts > 0) return VaultSyncResult.conflicts;
      return VaultSyncResult.done;
    } finally {
      _busy = false;
    }
  }

  Future<bool> link(GitHubBackup backup, RemoteVault remote) async {
    final session = vault.session;
    final store = vault.store;
    final id = vault.selectedId;
    if (_busy || session == null || store == null || id == null || vault.owns(session) == false) return false;
    _busy = true;
    try {
      await backup.linkExistingVault(id, store, session, remote);
      return vault.owns(session) && backup.problem == null;
    } finally {
      _busy = false;
    }
  }

  Future<bool> restore(
    GitHubBackup backup,
    Uint8List bytes,
    String password, {
    RemoteVault? remote,
  }) async {
    final catalog = vault.catalog;
    if (_busy || catalog == null) return false;
    final epoch = vault.epoch;
    final target = catalog.newVault();
    _busy = true;
    try {
      if (remote != null) await backup.bindSynchronizedImport(target.id, remote);
      if (vault.accepts(epoch) == false) {
        if (remote != null) await backup.cancelSynchronizedImport(target.id);
        return false;
      }
      try {
        return await vault.importBytes(target, bytes, password);
      } catch (_) {
        if (remote != null && await target.store.exists() == false) {
          await backup.cancelSynchronizedImport(target.id);
        }
        rethrow;
      }
    } finally {
      _busy = false;
    }
  }
}
