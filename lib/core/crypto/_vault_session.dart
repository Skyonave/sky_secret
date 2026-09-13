part of 'vault_cipher.dart';

class VaultSession {
  late ProtectedBytes _key;
  var _lifetime = SecretLifetime();
  final _workers = <CancellableWorker<dynamic>>{};
  final _replacements = <VaultSession>{};
  Uint8List _prefix;
  Uint8List _encoded;
  List<VaultEntry> _entries;
  List<VaultFolder> _folders;
  String? _name;
  bool _locked = false;
  VaultRevision _revision;
  String writerId = VaultRevision.randomId();
  final _sealedRevisions = Expando<VaultRevision>();

  VaultSession._(
    Uint8List key,
    this._prefix,
    this._encoded,
    this._entries,
    this._folders,
    this._name,
    this._revision,
  ) {
    try {
      _key = ProtectedBytes(key);
      _entries = _entries.map((e) => VaultEntry._owned(e, _lifetime)).toList();
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  VaultRevision get revision => _revision;

  Future<T> runWorker<T>(CancellableWorker<T> worker) async {
    if (_locked) {
      worker.cancel();
      return await worker.result;
    }
    _workers.add(worker);
    try {
      final result = await worker.result;
      if (_locked) throw StateError('Vault is locked');
      return result;
    } finally {
      _workers.remove(worker);
    }
  }

  List<VaultEntry> get entries => List.unmodifiable(_entries);

  List<VaultEntry> prepareEntries(List<VaultEntry> entries) {
    if (_locked) throw StateError('Vault is locked');
    return entries.map((e) => VaultEntry._owned(e, _lifetime)).toList();
  }

  List<VaultFolder> get folders => List.unmodifiable(_folders);

  String? get name => _name;

  bool get isLocked => _locked;

  Uint8List get persistedBytes => Uint8List.fromList(_encoded);

  bool hasSameKeyEnvelope(VaultSession other) {
    if (_locked || other.isLocked) throw StateError('Vault is locked');
    if (_prefix.length == other._prefix.length) {
      for (var index = 0; index < _prefixLength; index++) {
        if (_prefix[index] == other._prefix[index]) continue;
        return false;
      }
      return true;
    }
    return false;
  }

  Future<VaultSession> openRevision(Uint8List bytes) async {
    if (_locked) throw StateError('Vault is locked');
    _validateEnvelope(bytes);
    bytes = Uint8List.fromList(bytes);
    for (var i = 0; i < _prefixLength; i++) {
      if (bytes[i] != _prefix[i]) throw const VaultUnlockException();
    }
    final revision = await runWorker(_startRevision(_key, bytes));
    _replacements.add(revision);
    return revision;
  }

  Future<VaultSession> openWithPassword(
    Uint8List bytes,
    String password,
  ) async {
    final child = await runWorker(_startUnlock(bytes, password));
    if (child.revision.lineage != revision.lineage) {
      child.lock();
      throw const VaultUnlockException();
    }
    _replacements.add(child);
    return child;
  }

  void validateAdoption(VaultSession source) {
    if (_locked || source.isLocked) throw StateError('Vault is locked');
    if (!source.revision.includes(revision) || source.revision.keyEpoch < revision.keyEpoch) {
      throw const VaultFormatException();
    }
    if (source.revision.keyEpoch == revision.keyEpoch) {
      for (var i = 0; i < _prefixLength; i++) {
        if (source._prefix[i] != _prefix[i]) throw const VaultUnlockException();
      }
    }
  }

  void adoptRevision(VaultSession source) {
    validateAdoption(source);
    final lifetime = SecretLifetime();
    final owned = source.entries.map((e) => VaultEntry._owned(e, lifetime)).toList();
    final key = source._key.read();
    try {
      final protected = ProtectedBytes(key);
      _lifetime.revoke();
      _key.destroy();
      _lifetime = lifetime;
      _key = protected;
      _prefix = Uint8List.fromList(source._prefix);
      _encoded = source.persistedBytes;
      _entries = owned;
      _folders = List.of(source.folders);
      _name = source.name;
      _revision = source.revision;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  void closeRevision(VaultSession revision) {
    _replacements.remove(revision);
    revision.lock();
  }

  Future<Uint8List> encrypt(
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
    VaultRevision? mergeRevision,
  }) async {
    if (_locked) throw StateError('Vault is locked');
    final prefix = Uint8List.fromList(_prefix);
    final groups = List<VaultFolder>.of(folders ?? _folders);
    final title = name ?? _name;
    final owned = entries.map((e) => VaultEntry._owned(e, _lifetime)).toList();
    final revision = _revision.advance(writerId, merge: mergeRevision);
    final worker = _startSeal(_key, prefix, owned, groups, title, revision);
    _workers.add(worker);
    try {
      final encoded = await worker.result;
      if (_locked) throw StateError('Vault is locked');
      _sealedRevisions[encoded] = revision;
      return encoded;
    } finally {
      _workers.remove(worker);
    }
  }

  Future<VaultSession> changePassword(String password) async {
    if (_locked) throw StateError('Vault is locked');
    final replacement = await VaultCipher.create(password, name: _name);
    try {
      if (_locked) throw StateError('Vault is locked');
      _replacements.add(replacement);
      replacement._revision = _revision.rotate();
      replacement.writerId = writerId;
      final entries = List<VaultEntry>.of(_entries);
      final folders = List<VaultFolder>.of(_folders);
      final encoded = await replacement.encrypt(entries, folders: folders);
      if (_locked) throw StateError('Vault is locked');
      replacement.acceptPersisted(encoded, entries, folders, _name);
      return replacement;
    } catch (_) {
      replacement.lock();
      rethrow;
    } finally {
      _replacements.remove(replacement);
    }
  }

  void acceptPersisted(
    Uint8List encoded,
    List<VaultEntry> entries,
    List<VaultFolder> folders,
    String? name, {
    VaultRevision? revision,
  }) {
    if (_locked) throw StateError('Vault is locked');
    final owned = entries.map((e) => VaultEntry._owned(e, _lifetime)).toList();
    _revision = revision ?? _sealedRevisions[encoded] ?? (throw StateError('Unauthenticated revision metadata'));
    _encoded = encoded;
    _entries = owned;
    _folders = List.of(folders);
    _name = name;
  }

  void lock() {
    _locked = true;
    _lifetime.revoke();
    for (final worker in _workers) {
      worker.cancel();
    }
    for (final replacement in _replacements) {
      replacement.lock();
    }
    _key.destroy();
    for (final entry in _entries) {
      entry._destroy();
    }
    _entries = const [];
    _folders = const [];
    _name = null;
  }
}
