import 'package:flutter/widgets.dart';

import '../../../core/crypto/crypto.dart';

class EntryValidationException implements Exception {
  final String code;

  const EntryValidationException(this.code);
}

class VaultEntryController {
  final title = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final notes = TextEditingController();
  final sshHost = TextEditingController();
  final sshPort = TextEditingController(text: '22');
  final _generator = PasswordGenerator();
  bool active = false;
  bool isSsh = false;
  String? id;
  String? folderId;
  int generationLength = 24;
  bool generationSymbols = true;

  List<TextEditingController> get _controllers => [title, username, password, notes, sshHost, sshPort];

  void start({VaultEntry? entry, String? parentId, bool ssh = false}) {
    clear();
    if (entry?.isDeleted == true) return;
    id = entry?.id;
    isSsh = entry?.isSsh ?? ssh;
    folderId = entry?.folderId ?? parentId;
    title.text = entry?.title ?? '';
    username.text = entry?.username ?? '';
    notes.text = entry?.notes ?? '';
    sshHost.text = entry?.ssh?.host ?? '';
    sshPort.text = (entry?.ssh?.port ?? 22).toString();
    if (entry == null) {
      if (isSsh == false) generate();
    } else {
      password.text = entry.password;
      if (password.text.isNotEmpty) generationLength = password.text.characters.length.clamp(12, 64);
    }
    active = true;
  }

  void generate() {
    password.text = _generator.generate(length: generationLength, symbols: generationSymbols);
  }

  VaultOrganization prepare(VaultSession session) {
    if (active == false || session.isLocked) throw StateError('No active editor');
    if (title.text.trim().isEmpty) throw const EntryValidationException('title');
    SshEndpoint? endpoint;
    if (isSsh) {
      endpoint = SshEndpoint(host: sshHost.text.trim().toLowerCase(), port: int.tryParse(sshPort.text) ?? 0);
      final valid =
          endpoint.isValid && SshEndpoint.validUsername(username.text) && SshEndpoint.validPassword(password.text);
      if (valid == false) throw const EntryValidationException('ssh-invalid');
    }
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    final previous = session.entries.where((entry) => entry.id == id).firstOrNull;
    if (id != null && (previous == null || previous.isDeleted)) throw StateError('Edited entry is unavailable');
    final entry = previous == null
        ? VaultEntry.create(
            title: title.text,
            username: username.text,
            password: password.text,
            notes: notes.text,
            folderId: folderId,
            ssh: endpoint,
          )
        : VaultEntry(
            id: previous.id,
            title: title.text,
            username: username.text,
            password: password.text,
            notes: notes.text,
            folderId: folderId,
            kind: isSsh ? VaultEntryKind.ssh : VaultEntryKind.text,
            ssh: endpoint,
            isFavorite: previous.isFavorite,
            conflictOf: previous.conflictOf,
            order: previous.order,
          );
    if (previous == null) {
      organization.appendEntries([entry], folderId);
    } else {
      final index = organization.entries.indexWhere((candidate) => candidate.id == id);
      organization.entries[index] = entry;
      if (previous.folderId != folderId) organization.move(VaultItem.entry(entry), folderId);
    }
    return organization;
  }

  void clear() {
    for (final controller in _controllers) {
      controller.clear();
    }
    active = false;
    isSsh = false;
    id = null;
    folderId = null;
  }

  void dispose() {
    clear();
    for (final controller in _controllers) {
      controller.dispose();
    }
  }
}
