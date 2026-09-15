import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'cancellable_worker.dart';
import 'master_password_policy.dart';
import 'password_normalization.dart';
import 'protected_memory.dart';
import 'ssh_endpoint.dart';
import 'totp.dart';
import 'vault_kdf_profile.dart';
import 'vault_revision.dart';

part '_vault_entry.dart';
part '_vault_attachment.dart';
part '_vault_folder.dart';
part '_vault_session.dart';

class VaultFormatException implements Exception {
  const VaultFormatException();
}

class VaultUnlockException implements Exception {
  const VaultUnlockException();
}

abstract final class VaultCipher {
  static const maxFileBytes = 72 * 1024 * 1024;
  static const maxAttachmentBytes = 20 * 1024 * 1024;
  static const maxTotalAttachmentBytes = 50 * 1024 * 1024;
  static const maxEntries = 1000;
  static const maxFiles = 5000;
  static const maxItems = maxEntries + maxFiles;
  static const maxFolders = 100;

  static Future<VaultSession> create(String password, {String? name}) => Isolate.run(() => _create(password, name));

  static Future<VaultSession> unlock(Uint8List bytes, String password) => Isolate.run(() => _unlock(bytes, password));

  static bool sameKeyEnvelope(Uint8List first, Uint8List second) {
    _validateEnvelope(first);
    _validateEnvelope(second);
    for (var index = 0; index < _prefixLength; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

CancellableWorker<Uint8List> _startSeal(
  ProtectedBytes protectedKey,
  Uint8List prefix,
  List<VaultEntry> entries,
  List<VaultFolder> folders,
  String? name,
  VaultRevision revision,
) => CancellableWorker(() async {
  final key = protectedKey.read();
  try {
    return await _seal(key, prefix, entries, folders, name, revision);
  } finally {
    key.fillRange(0, key.length, 0);
  }
});

const _headerLength = 56;
const _prefixLength = 116;
const _magic = [83, 77, 86, 65, 85, 76, 84, 0];
final _aes = AesGcm.with256bits();

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Future<SecretKey> _derive(String password, Uint8List header) async {
  if (password.isEmpty || password.length > 1024 * 1024) {
    throw const VaultFormatException();
  }
  final profile = _readKdfProfile(header);
  if (ByteData.sublistView(header).getUint32(8) == 2) {
    try {
      password = normalizeMasterPassword(password);
    } on FormatException {
      throw const VaultFormatException();
    }
  }
  final input = Uint8List.fromList(utf8.encode(password));
  final secret = SecretKeyData(input, overwriteWhenDestroyed: true);
  try {
    final derived = await DartArgon2id(
      memory: profile.memory,
      iterations: profile.iterations,
      parallelism: profile.parallelism,
      hashLength: 32,
      maxIsolates: 0,
    ).deriveKey(secretKey: secret, nonce: header.sublist(24, 40));
    final bytes = await derived.extractBytes();
    final owned = SecretKeyData(
      Uint8List.fromList(bytes),
      overwriteWhenDestroyed: true,
    );
    derived.destroy();
    return owned;
  } finally {
    secret.destroy();
    input.fillRange(0, input.length, 0);
  }
}

Future<VaultSession> _create(String password, String? name) async {
  MasterPasswordPolicy.validate(password);
  final header = Uint8List(_headerLength)..setRange(0, 8, _magic);
  final fields = ByteData.sublistView(header);
  fields.setUint32(8, 2);
  fields.setUint32(12, VaultKdfProfile.argon2id64MiB.id);
  header.setRange(24, 40, _randomBytes(16));
  header.setRange(40, 56, _randomBytes(16));
  final kek = await _derive(password, header);
  final key = _randomBytes(32);
  try {
    final wrapped = await _aes.encrypt(
      key,
      secretKey: kek,
      nonce: _randomBytes(12),
      aad: _aad('wrap', header),
    );
    final prefix = Uint8List.fromList([...header, ...wrapped.concatenation()]);
    final revision = VaultRevision(VaultRevision.randomId(), {});
    final encoded = await _seal(
      key,
      prefix,
      const [],
      const [],
      name,
      revision,
    );
    return VaultSession._(
      Uint8List.fromList(key),
      prefix,
      encoded,
      const [],
      const [],
      name,
      revision,
    );
  } finally {
    kek.destroy();
    key.fillRange(0, key.length, 0);
  }
}

void _validateEnvelope(Uint8List bytes) {
  if (bytes.length < _prefixLength + 28 || bytes.length > VaultCipher.maxFileBytes) {
    throw const VaultFormatException();
  }
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _magic[i]) throw const VaultFormatException();
  }
  _readKdfProfile(bytes);
}

VaultKdfProfile _readKdfProfile(Uint8List bytes) {
  final fields = ByteData.sublistView(bytes);
  const profile = VaultKdfProfile.argon2id64MiB;
  if (fields.getUint32(8) == 1 &&
      fields.getUint32(12) == profile.memory &&
      fields.getUint32(16) == profile.iterations &&
      fields.getUint32(20) == profile.parallelism) {
    return profile;
  }
  if (fields.getUint32(8) == 2 &&
      fields.getUint32(12) == profile.id &&
      fields.getUint32(16) == 0 &&
      fields.getUint32(20) == 0) {
    return profile;
  }
  throw const VaultFormatException();
}

List<int> _aad(String purpose, Uint8List prefix) => [
  ...utf8.encode('SMV${ByteData.sublistView(prefix).getUint32(8)}/$purpose'),
  ...prefix,
];

Future<VaultSession> _unlock(Uint8List bytes, String password) async {
  _validateEnvelope(bytes);
  final kek = await _derive(password, bytes.sublist(0, _headerLength));
  Uint8List? key;
  SecretKey? dataKey;
  List<int>? plain;
  try {
    key = Uint8List.fromList(
      await _aes.decrypt(
        SecretBox.fromConcatenation(
          bytes.sublist(56, 116),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: kek,
        aad: _aad('wrap', bytes.sublist(0, 56)),
      ),
    );
    dataKey = SecretKeyData(
      Uint8List.fromList(key),
      overwriteWhenDestroyed: true,
    );
    plain = await _aes.decrypt(
      SecretBox.fromConcatenation(
        bytes.sublist(116),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: dataKey,
      aad: _aad('data', bytes.sublist(0, 116)),
    );
    final contents = _decodeContents(plain);
    return VaultSession._(
      Uint8List.fromList(key),
      bytes.sublist(0, 116),
      Uint8List.fromList(bytes),
      contents.entries,
      contents.folders,
      contents.name,
      contents.revision ?? _legacyRevision(bytes),
    );
  } on SecretBoxAuthenticationError {
    throw const VaultUnlockException();
  } on FormatException {
    throw const VaultFormatException();
  } finally {
    kek.destroy();
    dataKey?.destroy();
    key?.fillRange(0, key.length, 0);
    if (plain != null) {
      for (var i = 0; i < plain.length; i++) {
        plain[i] = 0;
      }
    }
  }
}

({
  List<VaultEntry> entries,
  List<VaultFolder> folders,
  String? name,
  VaultRevision? revision,
})
_decodeContents(List<int> plain) {
  final json = jsonDecode(utf8.decode(plain));
  if (json is! Map<String, dynamic> ||
      json['entries'] is! List ||
      (json['entries'] as List).length >
          ([4, 5, 6, 7, 8, 9].contains(json['schemaVersion']) ? VaultCipher.maxItems : VaultCipher.maxEntries)) {
    throw const VaultFormatException();
  }
  final legacy = json.length == 1 && json.containsKey('entries');
  var rawFiles = 0;
  var rawEntries = 0;
  for (final value in json['entries'] as List) {
    if (value is! Map) throw const VaultFormatException();
    if ([4, 5, 6, 7, 8, 9].contains(json['schemaVersion']) && value['kind'] == 'file') {
      rawFiles++;
    } else {
      rawEntries++;
    }
    if (json['schemaVersion'] == 3 && value['attachments'] is List) {
      rawFiles += (value['attachments'] as List).length;
    }
    if (rawFiles > VaultCipher.maxFiles || rawEntries > VaultCipher.maxEntries) {
      throw const VaultFormatException();
    }
  }
  final organized = [6, 7, 8, 9].contains(json['schemaVersion']);
  if (!legacy &&
      (json.length != ([5, 6, 7, 8, 9].contains(json['schemaVersion']) ? 5 : 4) ||
          json['schemaVersion'] is! int ||
          ![2, 3, 4, 5, 6, 7, 8, 9].contains(json['schemaVersion']) ||
          !json.containsKey('name') ||
          !_validName(json['name']) ||
          json['folders'] is! List ||
          (json['folders'] as List).length > VaultCipher.maxFolders)) {
    throw const VaultFormatException();
  }
  final folders = legacy
      ? <VaultFolder>[]
      : (json['folders'] as List).map((value) {
          if (organized && (value is! Map || value.length != 4)) throw const VaultFormatException();
          return VaultFolder.fromJson(value, organized: organized);
        }).toList();
  final folderIds = folders.map((folder) => folder.id).toSet();
  if (folderIds.length != folders.length) throw const VaultFormatException();
  final foldersById = {for (final folder in folders) folder.id: folder};
  for (final folder in folders) {
    if (folder.parentId == null) continue;
    final parent = foldersById[folder.parentId];
    if (parent == null || parent.id == folder.id || parent.parentId != null) {
      throw const VaultFormatException();
    }
  }
  if (organized && (json['entries'] as List).any((value) => value is! Map || !value.containsKey('order'))) {
    throw const VaultFormatException();
  }
  final entries = (json['entries'] as List)
      .map(
        (value) => VaultEntry.fromJson(
          value,
          legacy: legacy,
          files: json['schemaVersion'] == 3 || [4, 5, 6, 7, 8, 9].contains(json['schemaVersion']),
          typed: [4, 5, 6, 7, 8, 9].contains(json['schemaVersion']),
          organized: organized,
          sshAllowed: [7, 8, 9].contains(json['schemaVersion']),
          metadata: [8, 9].contains(json['schemaVersion']),
          totpAllowed: json['schemaVersion'] == 9,
        ),
      )
      .toList();
  if (entries.map((e) => e.id).toSet().length != entries.length) {
    throw const VaultFormatException();
  }
  var total = 0;
  final attachmentIds = <String>{};
  for (final entry in entries) {
    for (final attachment in entry.attachments) {
      total += attachment.size;
      if (!attachmentIds.add(attachment.id) || total > VaultCipher.maxTotalAttachmentBytes) {
        throw const VaultFormatException();
      }
    }
  }
  if (entries.any(
    (entry) => entry.folderId != null && !folderIds.contains(entry.folderId),
  )) {
    throw const VaultFormatException();
  }
  final normalized = <VaultEntry>[];
  final entryIds = entries.map((e) => e.id).toSet();
  for (final entry in entries) {
    if ([4, 5, 6, 7, 8, 9].contains(json['schemaVersion']) || entry.attachments.isEmpty) {
      normalized.add(entry);
      continue;
    }
    normalized.add(
      VaultEntry(
        id: entry.id,
        title: entry.title,
        username: entry.username,
        password: entry.password,
        notes: entry.notes,
        folderId: entry.folderId,
      ),
    );
    for (final attachment in entry.attachments) {
      var id = 'file:${attachment.id}';
      while (!entryIds.add(id)) {
        id = '_$id';
      }
      normalized.add(
        VaultEntry.file(attachment, folderId: entry.folderId, id: id),
      );
    }
  }
  if (normalized.where((e) => !e.isFile).length > VaultCipher.maxEntries ||
      normalized.where((e) => e.isFile).length > VaultCipher.maxFiles) {
    throw const VaultFormatException();
  }
  if (!organized) {
    for (var index = 0; index < normalized.length; index++) {
      final entry = normalized[index];
      normalized[index] = entry.atPosition(entry.folderId, index * 1024);
    }
    for (var index = 0; index < folders.length; index++) {
      folders[index] = folders[index].atPosition(null, (normalized.length + index) * 1024);
    }
  }
  return (
    entries: normalized,
    folders: folders,
    name: legacy ? null : json['name'] as String?,
    revision: [5, 6, 7, 8, 9].contains(json['schemaVersion']) ? VaultRevision.fromJson(json['revision']) : null,
  );
}

bool _validName(dynamic name) => name == null || (name is String && name.trim().isNotEmpty && name.length <= 120);

bool _validOrder(dynamic order) => order is int && order >= 0 && order <= 9007199254740991;

Future<Uint8List> _seal(
  Uint8List key,
  Uint8List prefix,
  List<VaultEntry> entries,
  List<VaultFolder> folders,
  String? name,
  VaultRevision revision,
) async {
  final secret = SecretKeyData(
    Uint8List.fromList(key),
    overwriteWhenDestroyed: true,
  );
  Uint8List? plain;
  try {
    if (!_validName(name) || entries.length > VaultCipher.maxItems || folders.length > VaultCipher.maxFolders) {
      throw const VaultFormatException();
    }
    var codeUnits = 0, attachmentBytes = 0;
    for (final entry in entries) {
      for (final field in [
        entry.id,
        entry.title,
        entry.username,
        entry.password,
        entry.notes,
        entry.totp,
      ]) {
        codeUnits += field.length;
      }
      for (final attachment in entry.attachments) {
        attachmentBytes += attachment.size;
      }
      if (codeUnits > VaultCipher.maxFileBytes || attachmentBytes > VaultCipher.maxTotalAttachmentBytes) {
        throw const VaultFormatException();
      }
    }
    plain = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': entries.any((entry) => entry.hasTotp) ? 9 : 8,
          'revision': revision.toJson(),
          'name': name,
          'folders': folders.map((folder) => folder.toJson()).toList(),
          'entries': entries.map((entry) => entry.toJson()).toList(),
        }),
      ),
    );
    if (plain.length + _prefixLength + 28 > VaultCipher.maxFileBytes) {
      throw const VaultFormatException();
    }
    final checked = _decodeContents(plain);
    for (final entry in checked.entries) {
      entry._destroy();
    }
    final box = await _aes.encrypt(
      plain,
      secretKey: secret,
      nonce: _randomBytes(12),
      aad: _aad('data', prefix),
    );
    return Uint8List.fromList([...prefix, ...box.concatenation()]);
  } finally {
    secret.destroy();
    plain?.fillRange(0, plain.length, 0);
  }
}

VaultRevision _legacyRevision(Uint8List bytes) => VaultRevision(
  bytes.sublist(40, 56).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  {},
);
CancellableWorker<VaultSession> _startUnlock(
  Uint8List bytes,
  String password,
) => CancellableWorker(() => _unlock(bytes, password));
CancellableWorker<VaultSession> _startRevision(
  ProtectedBytes protected,
  Uint8List bytes,
) => CancellableWorker(() async {
  final key = protected.read();
  final secret = SecretKeyData(key, overwriteWhenDestroyed: true);
  List<int>? plain;
  try {
    plain = await _aes.decrypt(
      SecretBox.fromConcatenation(
        bytes.sublist(_prefixLength),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: secret,
      aad: _aad('data', bytes.sublist(0, _prefixLength)),
    );
    final contents = _decodeContents(plain);
    return VaultSession._(
      Uint8List.fromList(key),
      bytes.sublist(0, _prefixLength),
      bytes,
      contents.entries,
      contents.folders,
      contents.name,
      contents.revision ?? _legacyRevision(bytes),
    );
  } on SecretBoxAuthenticationError {
    throw const VaultUnlockException();
  } on FormatException {
    throw const VaultFormatException();
  } finally {
    secret.destroy();
    key.fillRange(0, key.length, 0);
    plain?.fillRange(0, plain.length, 0);
  }
});
