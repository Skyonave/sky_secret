import 'dart:io';
import 'dart:typed_data';

import '../../../core/crypto/crypto.dart';

class VaultSessionController {
  VaultStore? _store;
  VaultCatalog? _catalog;
  VaultSession? _session;
  List<VaultReference> _vaults = [];
  final _names = <String, String>{};
  String? _selectedId;
  bool _exists = false;
  bool _disposed = false;
  int _epoch = 0;
  Object? _opening;

  VaultSessionController({this._store, this._catalog});

  VaultStore? get store => _store;
  VaultCatalog? get catalog => _catalog;
  VaultSession? get session => _session;
  List<VaultReference> get vaults => List.unmodifiable(_vaults);
  Map<String, String> get names => Map.unmodifiable(_names);
  String? get selectedId => _selectedId;
  bool get exists => _exists;
  int get epoch => _epoch;

  bool accepts(int epoch) => _disposed == false && _epoch == epoch;

  bool owns(VaultSession session) => _disposed == false && _session == session && session.isLocked == false;

  Future<void> load() async {
    final epoch = _epoch;
    if (_store == null) {
      final catalog = _catalog ?? VaultCatalog.local();
      final vaults = await catalog.list();
      if (accepts(epoch) == false) return;
      if (vaults.isEmpty) vaults.add(catalog.legacy);
      _catalog = catalog;
      _vaults = vaults;
      _selectedId = vaults.first.id;
      _store = vaults.first.store;
    }
    final exists = await _store!.exists();
    if (accepts(epoch)) _exists = exists;
  }

  Future<void> select(String? id) async {
    final catalog = _catalog;
    if (catalog == null) return;
    lock();
    final epoch = _epoch;
    final vaults = await catalog.list();
    if (accepts(epoch) == false) return;
    final selected = id == null
        ? (vaults.isEmpty ? catalog.legacy : catalog.newVault())
        : vaults.where((vault) => vault.id == id).firstOrNull;
    if (selected == null) throw StateError('Selected vault is unavailable');
    if (id == null) vaults.add(selected);
    _vaults = vaults;
    _store = selected.store;
    _selectedId = selected.id;
    await load();
  }

  Future<bool> open(String password, {String? name}) async {
    final epoch = _epoch;
    final store = _store;
    if (store == null || _disposed) return false;
    final request = Object();
    _opening = request;
    final VaultSession opened;
    try {
      opened = _exists ? await store.unlock(password) : await store.create(password, name: name);
    } on VaultConflictException {
      if (accepts(epoch)) await load();
      rethrow;
    }
    if (accepts(epoch) == false || _opening != request) {
      opened.lock();
      return false;
    }
    _replace(opened);
    return true;
  }

  Future<bool> importFile(File file, String password) async {
    final catalog = _catalog;
    if (catalog == null || _disposed) return false;
    final epoch = _epoch;
    final target = catalog.newVault();
    final imported = await target.store.importFrom(file, password, allowed: () => accepts(epoch));
    return _acceptImport(target, imported, epoch);
  }

  Future<bool> importBytes(
    VaultReference target,
    Uint8List bytes,
    String password,
  ) async {
    final epoch = _epoch;
    if (_disposed) return false;
    final imported = await target.store.importEncryptedSnapshot(bytes, password, allowed: () => accepts(epoch));
    return _acceptImport(target, imported, epoch);
  }

  bool _acceptImport(
    VaultReference target,
    VaultSession imported,
    int epoch,
  ) {
    if (accepts(epoch) == false) {
      imported.lock();
      return false;
    }
    _store = target.store;
    _selectedId = target.id;
    _vaults.add(target);
    _replace(imported);
    return true;
  }

  Future<bool> changePassword(String current, String replacement) async {
    final session = _session;
    final store = _store;
    final epoch = _epoch;
    if (session == null || store == null || owns(session) == false) return false;
    final changed = await store.changePassword(session, current, replacement);
    if (accepts(epoch) == false) {
      changed.lock();
      return false;
    }
    _replace(changed);
    return true;
  }

  Future<bool> save(
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    final session = _session;
    final store = _store;
    if (session == null || store == null || owns(session) == false) return false;
    await store.save(session, entries, folders: folders, name: name);
    if (owns(session) == false) return false;
    rememberName();
    return true;
  }

  void rememberName() {
    final name = _session?.name;
    final id = _selectedId;
    if (name != null && id != null) _names[id] = name;
  }

  Future<void> deleteSelected() async {
    final store = _store;
    final id = _selectedId;
    final epoch = _epoch;
    if (store == null || _disposed) return;
    _opening = null;
    _session?.lock();
    _session = null;
    await store.delete(allowed: () => accepts(epoch) && _store == store);
    if (accepts(epoch) == false) return;
    _names.remove(id);
    _store = null;
    _selectedId = null;
    _exists = false;
    await load();
  }

  void _replace(VaultSession session) {
    _opening = null;
    if (_session == session) return;
    _session?.lock();
    _session = session;
    _exists = true;
    rememberName();
  }

  void lock() {
    _opening = null;
    _epoch++;
    _session?.lock();
    _session = null;
  }

  void dispose() {
    lock();
    _names.clear();
    _disposed = true;
  }
}
