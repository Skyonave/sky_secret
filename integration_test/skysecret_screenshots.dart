import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import '../test/manager_window_test.dart' show FakeClipboard, FakeDesktop;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture six SkySecret demo screenshots', (tester) async {
    final directory = await Directory.systemTemp.createTemp('skysecret-demo-');
    addTearDown(() => directory.delete(recursive: true));
    const demoPassword = 'DemoOnly-2026!';
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final seed = await store.create(demoPassword, name: 'Demo');
    await store.save(seed, [
      VaultEntry.create(
        title: 'Demo account',
        username: 'demo@example.invalid',
        password: 'DemoValue-2026!',
      ),
      VaultEntry.file(
        VaultAttachment.create(
          'example.env',
          utf8.encode('API_TOKEN=YOUR_TOKEN_HERE\n'),
        ),
      ),
    ]);
    seed.lock();
    final desktop = FakeDesktop();
    addTearDown(desktop.dispose);
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(460, 660),
        title: 'SkySecret — screenshots (demo)',
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Color(0xFF0B131B),
      ),
    );
    await windowManager.show();
    const capture = Key('skysecret-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: SkySecretApp(
          desktop: desktop,
          clipboard: FakeClipboard(),
          vaultStore: store,
          vaultPreferences: VaultPreferences(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vault-master')), demoPassword);
    await tester.tap(find.byKey(const Key('open-vault')));
    await tester.pumpAndSettle();

    Future<void> screenshot(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/qa/skysecret')
          ..createSync(recursive: true);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }

    for (final locale in AppLocale.values) {
      await LocaleSettings.setLocale(locale);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.vault));
      await tester.pumpAndSettle();
      await screenshot('vault-${locale.name}');
      await tester.tap(find.byKey(const Key('vault-settings')));
      await tester.pumpAndSettle();
      await screenshot('settings-${locale.name}');
      await tester.tap(find.text(t.cancel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.generator));
      await tester.pumpAndSettle();
      await screenshot('generator-${locale.name}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await windowManager.hide();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
