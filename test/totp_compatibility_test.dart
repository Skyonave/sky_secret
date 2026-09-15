import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/totp_session.dart';
import 'package:skysecret/ui/vault/controllers/vault_entry_controller.dart';

import 'vault_collection_test.dart' show saveRevision;
import 'vault_sections_test.dart' show fixture;

const _password = 'synthetic legacy password';
const _key = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const _uri = 'otpauth://totp/SkySecret?secret=$_key&algorithm=SHA1&digits=6&period=30';

Map<String, dynamic> _oldEntry(String id, {bool ssh = false, bool totp = true}) => {
  'id': id,
  'title': 'Synthetic $id',
  'username': 'tester',
  'password': 'synthetic saved password',
  'notes': 'synthetic saved notes',
  if (totp) 'totp': _uri,
  'folderId': 'synthetic-folder',
  'attachments': <Object>[],
  'kind': ssh ? 'ssh' : 'text',
  if (ssh) 'ssh': {'host': 'example.invalid', 'port': 2222},
  'conflictOf': 'synthetic-origin',
  'order': 4096,
  'favorite': true,
};

Map<String, dynamic> _contents(int schema, List<Map<String, dynamic>> entries) => {
  'schemaVersion': schema,
  'name': 'Synthetic old vault',
  'folders': [
    {'id': 'synthetic-folder', 'name': 'Synthetic folder', 'parentId': null, 'order': 1024},
  ],
  'entries': entries,
  'revision': VaultRevision(VaultRevision.randomId(), {}).toJson(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final schema in [8, 9]) {
    test('previous schema $schema opens unchanged and retains every field after editing and saving', () async {
      final dir = await Directory.systemTemp.createTemp('skysecret-totp-compat-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/synthetic.smv');
      final records = [
        _oldEntry('text-entry', totp: schema == 9),
        _oldEntry('ssh-entry', ssh: true, totp: schema == 9),
        {..._oldEntry('trashed-entry', totp: schema == 9), 'deletedAt': 123},
      ];
      final bytes = await fixture(_contents(schema, records));
      await file.writeAsBytes(bytes);
      final store = VaultStore(file: file);
      final session = await store.unlock(_password);
      addTearDown(session.lock);
      expect(await file.readAsBytes(), bytes);
      expect(session.persistedBytes, bytes);
      expect(session.entries.map((entry) => entry.toJson()).toList(), records);
      final editor = VaultEntryController();
      addTearDown(editor.dispose);
      for (final id in ['text-entry', 'ssh-entry']) {
        editor.start(entry: session.entries.firstWhere((entry) => entry.id == id));
        expect(editor.isTotp, isFalse);
        expect(editor.totp.text, isEmpty);
        editor.notes.text = 'synthetic edited notes';
        final changes = editor.prepare(session);
        await store.save(session, changes.entries, folders: changes.folders);
      }
      final reopened = await store.unlock(_password);
      addTearDown(reopened.lock);
      for (final expected in records) {
        final id = expected['id'];
        expect(reopened.entries.firstWhere((entry) => entry.id == id).toJson(), {
          ...expected,
          if (id != 'trashed-entry') 'notes': 'synthetic edited notes',
        });
      }
      final codes = TotpSession(
        vault: reopened,
        isValid: () => true,
        copy: (_) async => true,
        clearClipboard: () async {},
        activity: () {},
      );
      final rows = await codes.snapshot(DateTime.fromMillisecondsSinceEpoch(59000));
      expect(rows.length, schema == 9 ? 2 : 0);
      if (schema == 9) expect(rows.map((row) => row['code']), everyElement('287082'));
      final retained = reopened.entries.first.inFolder(null);
      reopened.lock();
      expect(() => retained.password, throwsStateError);
      expect(() => retained.totp, throwsStateError);
    });
  }

  test('legacy TOTP keys survive independent password edits and synchronization', () async {
    final bytes = await fixture(_contents(9, [_oldEntry('text-entry')]));
    final base = await VaultCipher.unlock(bytes, _password);
    final local = await VaultCipher.unlock(bytes, _password);
    final remote = await VaultCipher.unlock(bytes, _password);
    addTearDown(base.lock);
    addTearDown(local.lock);
    addTearDown(remote.lock);
    await saveRevision(local, [
      VaultEntry.fromJson({...local.entries.single.toJson(), 'notes': 'synthetic local edit'}),
    ]);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(merged.conflicts, 0);
    expect(merged.entries.single.totp, _uri);
    expect(merged.entries.single.password, 'synthetic saved password');
    expect(merged.entries.single.notes, 'synthetic local edit');
    expect(merged.entries.single.kind, VaultEntryKind.text);
  });
}
