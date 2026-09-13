import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/i18n/translations.g.dart';

import '../test/manager_window_test.dart' show FakeClipboard, FakeDesktop;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final failCleanup in [false, true]) {
    testWidgets('synthetic UI rotation, restart and export; cleanup failure: $failCleanup', (tester) async {
      final directory = await Directory.systemTemp.createTemp('sm-security-native-');
      addTearDown(() => directory.delete(recursive: true));
      var obstructed = failCleanup;
      final store = VaultStore(
        file: File('${directory.path}/vault.smv'),
        beforeSnapshotCleanup: () async {
          if (obstructed) throw const FileSystemException('Synthetic cleanup obstruction');
        },
      );
      const oldPassword = 'synthetic old security phrase';
      const newPassword = 'synthetic new café security phrase';
      final seed = await store.create(oldPassword);
      await store.save(seed, [VaultEntry.create(title: 'Synthetic record', password: 'Synthetic account secret')]);
      final exported = File('${directory.path}/independent.smv');
      await store.exportTo(seed, exported);
      await store.cacheBaseline('a' * 40, seed.persistedBytes);
      seed.lock();
      await LocaleSettings.setLocale(AppLocale.en);

      Future<void> tap(String key) async {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> waitFor(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsOneWidget);
      }

      Future<void> mount() async {
        await tester.pumpWidget(SkySecretApp(desktop: FakeDesktop(), clipboard: FakeClipboard(), vaultStore: store));
        await waitFor(find.byKey(const Key('vault-master')));
      }

      await mount();
      await tester.enterText(find.byKey(const Key('vault-master')), oldPassword);
      await tap('open-vault');
      await waitFor(find.text('Synthetic record'));
      await tap('vault-settings');
      await tap('change-master');
      expect(find.text(t.vaultPasswordBackupWarning), findsOneWidget);
      await tester.enterText(find.byKey(const Key('current-master')), oldPassword);
      await tester.enterText(find.byKey(const Key('transfer-master')), newPassword);
      await tester.enterText(find.byKey(const Key('transfer-confirm')), newPassword);
      await tap('confirm-password-action');
      await waitFor(find.text(failCleanup ? t.vaultSnapshotCleanupWarning : t.vaultPasswordChanged));
      expect((await store.history()).isNotEmpty, failCleanup);
      expect(await store.readBaseline('a' * 40), failCleanup ? isNotNull : isNull);
      obstructed = false;
      await expectLater(store.unlock(oldPassword), throwsA(isA<VaultUnlockException>()));
      final oldExport = await VaultStore(file: exported).unlock(oldPassword);
      expect(oldExport.entries.single.title, 'Synthetic record');
      oldExport.lock();

      await tester.pumpWidget(const SizedBox.shrink());
      await mount();
      await tester.enterText(find.byKey(const Key('vault-master')), 'synthetic new cafe\u0301 security phrase');
      await tap('open-vault');
      await waitFor(find.text('Synthetic record'));
      expect(await store.history(), isEmpty);
      expect(await store.readBaseline('a' * 40), isNull);
      await tap('lock-vault');
      await waitFor(find.byKey(const Key('vault-master')));
      expect(find.text('Synthetic record'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
