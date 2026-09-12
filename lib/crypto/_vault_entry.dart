part of 'vault_cipher.dart';

enum VaultEntryKind { text, file, ssh }

class VaultEntry {
  final String id;
  final String title;
  final String? conflictOf;
  final int order;
  final ProtectedText _username;
  final ProtectedText _password;
  final ProtectedText _notes;
  final String? folderId;
  final List<VaultAttachment> attachments;
  final VaultEntryKind kind;
  final SshEndpoint? ssh;

  VaultEntry({
    required this.id,
    required this.title,
    required String username,
    required String password,
    required String notes,
    this.folderId,
    List<VaultAttachment> attachments = const [],
    this.kind = VaultEntryKind.text,
    this.ssh,
    this.conflictOf,
    this.order = 0,
  }) : _username = ProtectedText(username),
       _password = ProtectedText(password),
       _notes = ProtectedText(notes),
       attachments = List.unmodifiable(attachments);

  factory VaultEntry.create({
    required String title,
    String username = '',
    String password = '',
    String notes = '',
    String? folderId,
    List<VaultAttachment> attachments = const [],
    SshEndpoint? ssh,
  }) => VaultEntry(
    id: base64UrlEncode(_randomBytes(16)),
    title: title,
    username: username,
    password: password,
    notes: notes,
    folderId: folderId,
    attachments: List.unmodifiable(attachments),
    kind: ssh == null ? VaultEntryKind.text : VaultEntryKind.ssh,
    ssh: ssh,
  );

  String get username => _username.read();

  String get password => _password.read();

  String get notes => _notes.read();

  bool get hasPassword => !_password.isEmpty;

  bool get isSsh => kind == VaultEntryKind.ssh;

  bool get isFile => kind == VaultEntryKind.file;

  factory VaultEntry.file(
    VaultAttachment file, {
    String? folderId,
    String? id,
  }) => VaultEntry(
    id: id ?? base64UrlEncode(_randomBytes(16)),
    title: file.name,
    username: '',
    password: '',
    notes: '',
    folderId: folderId,
    kind: VaultEntryKind.file,
    attachments: List.unmodifiable([file]),
  );

  VaultEntry._inFolder(VaultEntry source, this.folderId)
    : id = source.id,
      title = source.title,
      _username = source._username,
      _password = source._password,
      _notes = source._notes,
      attachments = source.attachments,
      kind = source.kind,
      ssh = source.ssh,
      conflictOf = source.conflictOf,
      order = source.order;

  VaultEntry inFolder(String? folderId) => VaultEntry._inFolder(this, folderId);

  VaultEntry._position(
    VaultEntry source,
    this.folderId,
    this.order,
  ) : id = source.id,
      title = source.title,
      _username = source._username,
      _password = source._password,
      _notes = source._notes,
      attachments = source.attachments,
      kind = source.kind,
      ssh = source.ssh,
      conflictOf = source.conflictOf;

  VaultEntry atPosition(String? folderId, int order) => VaultEntry._position(this, folderId, order);

  VaultEntry._owned(VaultEntry source, SecretLifetime lifetime)
    : id = source.id,
      title = source.title,
      _username = source._username.ownFor(lifetime),
      _password = source._password.ownFor(lifetime),
      _notes = source._notes.ownFor(lifetime),
      folderId = source.folderId,
      attachments = List.unmodifiable(
        source.attachments.map((a) => VaultAttachment._owned(a, lifetime)),
      ),
      kind = source.kind,
      ssh = source.ssh,
      conflictOf = source.conflictOf,
      order = source.order;

  VaultEntry._conflict(VaultEntry source, this.conflictOf)
    : id = source.id,
      title = source.title,
      _username = source._username,
      _password = source._password,
      _notes = source._notes,
      folderId = source.folderId,
      attachments = source.attachments,
      kind = source.kind,
      ssh = source.ssh,
      order = source.order;

  VaultEntry withConflict(String? id) => VaultEntry._conflict(this, id);

  void _destroy() {
    _username.destroy();
    _password.destroy();
    _notes.destroy();
    for (final attachment in attachments) {
      attachment._bytes.destroy();
    }
  }

  Map<String, dynamic> toJson() => {
    _VaultEntryJson.id: id,
    _VaultEntryJson.title: title,
    _VaultEntryJson.username: username,
    _VaultEntryJson.password: password,
    _VaultEntryJson.notes: notes,
    _VaultEntryJson.folderId: folderId,
    _VaultEntryJson.attachments: attachments.map((a) => a.toJson()).toList(),
    _VaultEntryJson.kind: kind.name,
    if (ssh != null) _VaultEntryJson.ssh: ssh!.toJson(),
    _VaultEntryJson.conflictOf: conflictOf,
    _VaultEntryJson.order: order,
  };

  static VaultEntry fromJson(
    dynamic value, {
    bool legacy = false,
    bool files = true,
    bool typed = true,
    bool organized = true,
    bool sshAllowed = true,
  }) {
    if (value is Map<String, dynamic> && value[_VaultEntryJson.kind] == _VaultEntryJson.ssh) {
      if (legacy || !typed || !sshAllowed) throw const VaultFormatException();
      final endpoint = value[_VaultEntryJson.ssh];
      if (endpoint is! Map<String, dynamic> ||
          endpoint.length != 2 ||
          endpoint['host'] is! String ||
          endpoint['port'] is! int) {
        throw const VaultFormatException();
      }
      final ssh = SshEndpoint(host: endpoint['host'], port: endpoint['port']);
      final plain = {...value}..remove(_VaultEntryJson.ssh);
      plain[_VaultEntryJson.kind] = 'text';
      final entry = fromJson(plain, organized: organized, sshAllowed: false);
      if (!ssh.isValid || !SshEndpoint.validUsername(entry.username) || !SshEndpoint.validPassword(entry.password)) {
        throw const VaultFormatException();
      }
      return VaultEntry(
        id: entry.id,
        title: entry.title,
        username: entry.username,
        password: entry.password,
        notes: entry.notes,
        folderId: entry.folderId,
        order: entry.order,
        conflictOf: entry.conflictOf,
        kind: VaultEntryKind.ssh,
        ssh: ssh,
      );
    }
    if (organized && value is Map<String, dynamic> && value.containsKey(_VaultEntryJson.order)) {
      if (!_validOrder(value[_VaultEntryJson.order])) throw const VaultFormatException();
      final entry = fromJson(
        {...value}..remove(_VaultEntryJson.order),
        legacy: legacy,
        files: files,
        typed: typed,
        organized: false,
        sshAllowed: sshAllowed,
      );
      return entry.atPosition(entry.folderId, value[_VaultEntryJson.order] as int);
    }
    if (value is! Map<String, dynamic> ||
        (typed && !legacy
            ? (value.length != 8 && value.length != 9) ||
                  (value.length == 9 && !value.containsKey(_VaultEntryJson.conflictOf)) ||
                  (value[_VaultEntryJson.conflictOf] != null &&
                      (value[_VaultEntryJson.conflictOf] is! String ||
                          (value[_VaultEntryJson.conflictOf] as String).isEmpty ||
                          (value[_VaultEntryJson.conflictOf] as String).length > 65536))
            : value.length != (legacy ? 5 : (files ? 7 : 6))) ||
        (!legacy && typed && !['text', 'file'].contains(value[_VaultEntryJson.kind])) ||
        (!legacy &&
            files &&
            (value[_VaultEntryJson.attachments] is! List ||
                (value[_VaultEntryJson.attachments] as List).length > 100)) ||
        (!legacy &&
            (!value.containsKey(_VaultEntryJson.folderId) ||
                (value[_VaultEntryJson.folderId] != null &&
                    (value[_VaultEntryJson.folderId] is! String ||
                        (value[_VaultEntryJson.folderId] as String).length > 64)))) ||
        ![
          _VaultEntryJson.id,
          _VaultEntryJson.title,
          _VaultEntryJson.username,
          _VaultEntryJson.password,
          _VaultEntryJson.notes,
        ].every(
          (key) => value[key] is String && (value[key] as String).length <= 65536,
        ) ||
        (value[_VaultEntryJson.id] as String).isEmpty ||
        (value[_VaultEntryJson.title] as String).trim().isEmpty) {
      throw const VaultFormatException();
    }
    final attachments = legacy || !files
        ? <VaultAttachment>[]
        : (value[_VaultEntryJson.attachments] as List).map(VaultAttachment.fromJson).toList();
    final kind = !legacy && typed && value[_VaultEntryJson.kind] == 'file' ? VaultEntryKind.file : VaultEntryKind.text;
    if (!legacy &&
        typed &&
        (kind == VaultEntryKind.file
            ? (attachments.length != 1 ||
                  value[_VaultEntryJson.title] != attachments.single.name ||
                  value[_VaultEntryJson.username] != '' ||
                  value[_VaultEntryJson.password] != '' ||
                  value[_VaultEntryJson.notes] != '')
            : attachments.isNotEmpty)) {
      throw const VaultFormatException();
    }
    return VaultEntry(
      id: value[_VaultEntryJson.id],
      title: value[_VaultEntryJson.title],
      username: value[_VaultEntryJson.username],
      password: value[_VaultEntryJson.password],
      notes: value[_VaultEntryJson.notes],
      folderId: legacy ? null : value[_VaultEntryJson.folderId],
      attachments: List.unmodifiable(attachments),
      kind: kind,
      conflictOf: value[_VaultEntryJson.conflictOf] as String?,
    );
  }
}

abstract final class _VaultEntryJson {
  static const id = 'id';
  static const title = 'title';
  static const username = 'username';
  static const password = 'password';
  static const notes = 'notes';
  static const folderId = 'folderId';
  static const attachments = 'attachments';
  static const kind = 'kind';
  static const ssh = 'ssh';
  static const conflictOf = 'conflictOf';
  static const order = 'order';
}
