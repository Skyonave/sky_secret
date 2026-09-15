import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/vault/controllers/vault_entry_controller.dart';

void main() {
  test('a generated value starts a draft without saving an entry', () {
    final editor = VaultEntryController();
    addTearDown(editor.dispose);
    expect(editor.applyGeneratedPassword('Synthetic generated value'), isTrue);
    expect(editor.active, isTrue);
    expect(editor.id, isNull);
    expect(editor.title.text, isEmpty);
    expect(editor.password.text, 'Synthetic generated value');
  });

  test('applying a generated value preserves all other draft fields', () {
    final editor = VaultEntryController();
    addTearDown(editor.dispose);
    editor.start(parentId: 'synthetic-folder', ssh: true);
    editor.title.text = 'Synthetic entry';
    editor.username.text = 'synthetic-user';
    editor.notes.text = 'Synthetic notes';
    editor.sshHost.text = 'example.invalid';
    editor.sshPort.text = '2222';
    expect(editor.applyGeneratedPassword('Synthetic generated value'), isTrue);
    expect(editor.password.text, 'Synthetic generated value');
    expect(editor.title.text, 'Synthetic entry');
    expect(editor.username.text, 'synthetic-user');
    expect(editor.notes.text, 'Synthetic notes');
    expect(editor.sshHost.text, 'example.invalid');
    expect(editor.sshPort.text, '2222');
    expect(editor.folderId, 'synthetic-folder');
    expect(editor.isSsh, isTrue);
  });

  test('an authenticator draft cannot be replaced by a generated password', () {
    final editor = VaultEntryController();
    addTearDown(editor.dispose);
    editor.start(authenticator: true);
    editor.title.text = 'Synthetic authenticator';
    editor.totp.text = 'Synthetic setup';
    expect(editor.applyGeneratedPassword('Synthetic generated value'), isFalse);
    expect(editor.title.text, 'Synthetic authenticator');
    expect(editor.totp.text, 'Synthetic setup');
    expect(editor.password.text, isEmpty);
    expect(editor.isTotp, isTrue);
  });
}
