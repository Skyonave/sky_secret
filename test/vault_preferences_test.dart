import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';

void main() {
  test('capture defaults off, persists independently and failed writes preserve it', () async {
    final directory = await Directory.systemTemp.createTemp('sky-capture-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preferences.json');
    await file.writeAsString('{"version":1,"autoLockEnabled":true}');
    final preferences = VaultPreferences(file: file);
    await preferences.loadAutoLock();
    expect(preferences.captureAllowed, isFalse);
    await preferences.save(true, lockWhenHidden: false, captureAllowed: true);
    final restored = VaultPreferences(file: file);
    await restored.loadAutoLock();
    expect(restored.captureAllowed, isTrue);
    await restored.saveAutoLock(false);
    final finalRead = VaultPreferences(file: file);
    expect(await finalRead.loadAutoLock(), isFalse);
    expect(finalRead.captureAllowed, isTrue);
    expect(finalRead.lockWhenHidden, isFalse);
    final previous = await file.readAsString();
    await file.rename('${file.path}.saved');
    await Directory(file.path).create();
    await expectLater(
      finalRead.save(true, lockWhenHidden: true, captureAllowed: false),
      throwsA(isA<FileSystemException>()),
    );
    expect(finalRead.captureAllowed, isTrue);
    expect(await File('${file.path}.saved').readAsString(), previous);
    await Directory(file.path).delete();
    await File('${file.path}.saved').rename(file.path);
    await file.writeAsString('{"version":1,"autoLockEnabled":true,"captureAllowed":"true"}');
    final invalid = VaultPreferences(file: file);
    await expectLater(invalid.loadAutoLock(), throwsFormatException);
    expect(invalid.captureAllowed, isFalse);
  });

  test(
    'hide locking defaults on for legacy settings and persists independently',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sky-hide-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/preferences.json');
      await file.writeAsString('{"version":1,"autoLockEnabled":false}');
      final preferences = VaultPreferences(file: file);
      expect(await preferences.loadAutoLock(), isFalse);
      expect(preferences.lockWhenHidden, isTrue);
      await preferences.save(false, lockWhenHidden: false);
      final reloaded = VaultPreferences(file: file);
      expect(await reloaded.loadAutoLock(), isFalse);
      expect(reloaded.lockWhenHidden, isFalse);
      await reloaded.saveAutoLock(true);
      final finalRead = VaultPreferences(file: file);
      expect(await finalRead.loadAutoLock(), isTrue);
      expect(finalRead.lockWhenHidden, isFalse);
      await file.writeAsString(
        '{"version":1,"autoLockEnabled":false,"lockWhenHidden":"false"}',
      );
      await expectLater(finalRead.loadAutoLock(), throwsFormatException);
      await file.rename('${file.path}.saved');
      await Directory(file.path).create();
      await expectLater(
        finalRead.save(false, lockWhenHidden: true),
        throwsA(isA<FileSystemException>()),
      );
      expect(finalRead.lockWhenHidden, isFalse);
    },
  );

  test(
    'auto-lock defaults on and persists both values across instances',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-preferences-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/vault_preferences.json');
      final preferences = VaultPreferences(file: file);
      expect(await preferences.loadAutoLock(), isTrue);
      await preferences.saveAutoLock(false);
      expect(await VaultPreferences(file: file).loadAutoLock(), isFalse);
      await preferences.saveAutoLock(true);
      expect(await VaultPreferences(file: file).loadAutoLock(), isTrue);
      await file.writeAsString('{"version":1,"autoLockEnabled":"false"}');
      await expectLater(preferences.loadAutoLock(), throwsFormatException);
    },
  );
}
