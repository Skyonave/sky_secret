import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

void main() {
  test('long unique passphrases need no composition rules', () {
    for (final value in [
      '', 'short phrase', '                ', 'password12345678',
      'correct horse battery staple', 'abcdabcdabcdabcd',
      '1234567890123456', 'abcdefghijklmnop',
      'synthetic\nlong passphrase',
      'A1!😀😀😀😀😀😀😀😀😀😀😀😀',
      'A1!e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301e\u0301',
    ]) {
      expect(MasterPasswordPolicy.accepts(value), isFalse, reason: 'Synthetic rejected fixture');
    }
    for (final value in [
      'violet boats drift over quiet lakes',
      'тихие лодки плывут над озером',
      'UPPERCASE WORDS CAN FORM A PHRASE',
      'sixteen letters!', 'A1!😀😀😀😀😀😀😀😀😀😀😀😀😀',
      'the word password is allowed inside a long phrase',
    ]) {
      expect(MasterPasswordPolicy.accepts(value), isTrue, reason: 'Synthetic accepted fixture');
    }
  });
  test(
    'weak creation leaves no file; legacy import and unlock still work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-policy-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = VaultStore(file: File('${directory.path}/new.smv'));
      await expectLater(
        destination.create('weak'),
        throwsA(isA<MasterPasswordPolicyException>()),
      );
      expect(await destination.file.exists(), isFalse);

      final source = File('${directory.path}/legacy.smv');
      final original = await fixture({'entries': <dynamic>[]});
      await source.writeAsBytes(original);
      const oldPassword = 'synthetic legacy password';
      final session = await destination.importFrom(source, oldPassword);
      addTearDown(session.lock);
      await expectLater(
        destination.changePassword(session, oldPassword, 'weak'),
        throwsA(isA<MasterPasswordPolicyException>()),
      );
      expect(session.isLocked, isFalse);
      expect(await destination.file.readAsBytes(), original);
      final reopened = await destination.unlock(oldPassword);
      reopened.lock();

      const newPassword = 'Synthetic new password 1!';
      final changed = await destination.changePassword(
        session,
        oldPassword,
        newPassword,
      );
      changed.lock();
      final current = await destination.unlock(newPassword);
      current.lock();
      await expectLater(
        destination.unlock(oldPassword),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(await source.readAsBytes(), original);
    },
  );
}
