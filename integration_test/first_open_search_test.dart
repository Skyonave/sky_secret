import 'dart:io';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/windows/hidden_window_frame.dart';
import 'package:skysecret/core/os/windows/desktop_controller.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('first unlock and search keep one native window; Escape and blur hide it', (tester) async {
    final directory = await Directory.systemTemp.createTemp('skysecret-first-open-');
    final password = List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16)).join();
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final fixture = await store.create(password, name: 'Integration fixture');
    fixture.lock();
    final desktop = DesktopController(settings: ShortcutStore(file: File('${directory.path}/settings.json')));
    addTearDown(() async {
      await desktop.hide();
      await prepareHiddenWindowFrame();
      await tester.pumpWidget(const SizedBox.shrink());
      await desktop.releaseResources();
      await directory.delete(recursive: true);
    });
    await LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      SkySecretApp(
        desktop: desktop,
        vaultCatalog: VaultCatalog(directory: directory),
        vaultPreferences: VaultPreferences(),
      ),
    );
    await desktop.initialize();
    expect(desktop.notice, isNull);
    expect(await windowManager.isVisible(), isFalse, reason: 'Tray-only startup');
    final managerId = await windowManager.getId();

    Future<void> waitFor(Future<bool> Function() condition, String description) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (await condition() == false) {
        if (DateTime.now().isAfter(deadline)) fail(description);
        await prepareHiddenWindowFrame();
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    for (var cycle = 0; cycle < 2; cycle++) {
      await desktop.toggle();
      await tester.pumpAndSettle();
      expect(await windowManager.isVisible(), isTrue);
      expect(await windowManager.isFocused(), isTrue);
      final managerBounds = await windowManager.getBounds();
      await tester.enterText(find.byKey(const Key('vault-master')), password);
      await tester.tap(find.byKey(const Key('open-vault')));
      await waitFor(() async => find.text('Integration fixture').evaluate().isNotEmpty, 'Vault did not unlock');
      await tester.pumpAndSettle();
      expect(await windowManager.isFocused(), isTrue, reason: 'Unlock must preserve native focus');
      expect(await WindowController.getAll(), hasLength(1), reason: 'Unlock must not start a search engine');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF, physicalKey: PhysicalKeyboardKey.keyF);
      await waitFor(
        () async => find.byKey(const Key('vault-search-query')).evaluate().isNotEmpty,
        'F did not open search on cycle $cycle',
      );
      await tester.pumpAndSettle();
      expect(await windowManager.getId(), managerId);
      expect(await WindowController.getAll(), hasLength(1));
      expect(await windowManager.isFocused(), isTrue);
      expect(await windowManager.getSize(), const Size(640, 460));
      final center = await calcWindowPosition(const Size(640, 460), Alignment.center);
      expect((await windowManager.getPosition() - center).distance, lessThan(2));
      await tester.enterText(find.byKey(const Key('vault-search-query')), 'fixture');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await waitFor(() async => await windowManager.isVisible() == false, 'Escape left manager visible');
      await waitFor(
          () async => await windowManager.getSize() == managerBounds.size,
        'Search did not restore manager size',
      );
    }

    await desktop.toggle();
    await tester.pumpAndSettle();
    await windowManager.blur();
    await waitFor(() async => await windowManager.isVisible() == false, 'Native blur left manager visible');
    expect(tester.takeException(), isNull);
  });
}
