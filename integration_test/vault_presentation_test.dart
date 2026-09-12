import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/desktop/desktop_controller.dart';
import 'package:skysecret/desktop/shortcut_settings.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import '../test/manager_window_test.dart' show FakeClipboard;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native vault create, edit, lock and reopen; compact ru/en layout',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-vault-native-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final desktop = DesktopController(
        settings: ShortcutStore(file: File('${directory.path}/settings.json')),
      );
      addTearDown(desktop.releaseResources);
      final store = VaultStore(file: File('${directory.path}/vault.smv'));
      const capture = Key('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: SkySecretApp(
            desktop: desktop,
            clipboard: FakeClipboard(),
            vaultCatalog: VaultCatalog(directory: directory),
          ),
        ),
      );
      await desktop.initialize();
      await desktop.show();
      await tester.pumpAndSettle();

      Future<void> screenshot(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/qa')..createSync(recursive: true);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      for (final locale in AppLocale.values) {
        await LocaleSettings.setLocale(locale);
        for (final size in [const Size(460, 600), const Size(400, 520)]) {
          await windowManager.setSize(size);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('open-vault')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await screenshot('vault-create-${locale.name}-${size.width.toInt()}');
        }
      }
      await LocaleSettings.setLocale(AppLocale.ru);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Synthetic integration phrase',
      );
      await tester.enterText(
        find.byKey(const Key('vault-confirm')),
        'Synthetic integration phrase',
      );
      await tap('open-vault');
      await tap('vault-heading');
      await tester.enterText(
        find.byKey(const Key('vault-inline-name')),
        'Мой тестовый сейф',
      );
      await tap('confirm-vault-name');
      await tap('add-folder');
      await tester.enterText(
        find.byKey(const Key('vault-name-input')),
        'Работа',
      );
      await tap('confirm-name');
      await tap('add-entry');
      await tester.enterText(
        find.byKey(const Key('entry-title')),
        'Тестовая запись',
      );
      await tester.enterText(
        find.byKey(const Key('entry-username')),
        'test-user',
      );
      await tester.enterText(
        find.byKey(const Key('entry-password')),
        'Synthetic integration secret',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await screenshot('vault-editor-ru-400');
      await tap('save-entry');
      expect(find.text('Тестовая запись'), findsOneWidget);
      final start = tester.getCenter(find.text('Тестовая запись'));
      final destination = tester.getCenter(find.text('Работа'));
      await tester.dragFrom(start, destination - start);
      await tester.pumpAndSettle();
      final verify = await store.unlock('Synthetic integration phrase');
      expect(verify.name, 'Мой тестовый сейф');
      expect(verify.entries.single.folderId, verify.folders.single.id);
      verify.lock();
      await screenshot('vault-entries-ru-400');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('vault-heading'))),
      );
      await tester.pumpAndSettle();
      await screenshot('vault-heading-hover-ru-400');
      await mouse.moveTo(tester.getCenter(find.text('Работа')));
      await tester.pumpAndSettle();
      await screenshot('vault-folder-hover-ru-400');
      await mouse.removePointer();
      await tap('lock-vault');
      expect(find.text('Тестовая запись'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Synthetic integration phrase',
      );
      await tap('open-vault');
      expect(find.text('Тестовая запись'), findsOneWidget);
      expect(find.text('Мой тестовый сейф'), findsWidgets);
      await tester.tap(find.byTooltip(t.vaultDeleteEntry));
      await tester.pumpAndSettle();
      await tap('confirm-delete');
      expect(find.text('Тестовая запись'), findsNothing);
      await tap('lock-vault');
      await screenshot('vault-locked-ru-400');
      await tap('vault-settings');
      await screenshot('vault-settings-ru-400');
      await tap('auto-lock-switch');
      await tap('save-vault-preferences');
      final preferences = await File('${directory.path}/vault_preferences.json')
          .readAsString();
      expect(preferences, contains('"autoLockEnabled":false'));
      await tap('vault-switcher');
      final menuMouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await menuMouse.addPointer(location: Offset.zero);
      await menuMouse.moveTo(
        tester.getCenter(find.byKey(const Key('new-vault'))),
      );
      await tester.pumpAndSettle();
      await screenshot('vault-menu-ru-400');
      await menuMouse.removePointer();
      await tap('new-vault');
      await tester.enterText(
        find.byKey(const Key('vault-display-name')),
        'Второй сейф',
      );
      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Second synthetic phrase',
      );
      await tester.enterText(
        find.byKey(const Key('vault-confirm')),
        'Second synthetic phrase',
      );
      await tap('open-vault');
      expect(await VaultCatalog(directory: directory).list(), hasLength(2));
      await tap('vault-switcher');
      await tester.tap(find.text('Мой тестовый сейф').last);
      await tester.pumpAndSettle();
      expect(find.text(t.vaultLocked), findsOneWidget);
      expect(find.byKey(const Key('lock-vault')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Synthetic integration phrase',
      );
      await tap('open-vault');
      expect(find.text('Работа'), findsOneWidget);
      await screenshot('vault-multiple-ru-400');
      await tap('lock-vault');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
