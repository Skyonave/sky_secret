import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/desktop/desktop_controller.dart';
import 'package:skysecret/desktop/shortcut_settings.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/password_preview_assertions.dart';

final _keyEvent = DynamicLibrary.open('user32.dll')
    .lookupFunction<
      Void Function(Uint8, Uint8, Uint32, UintPtr),
      void Function(int, int, int, int)
    >('keybd_event');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'generator fits, real shortcut input is visible, corner placement',
    (tester) async {
      addTearDown(() {
        _keyEvent(0x77, 0x42, 2, 0);
        _keyEvent(0x11, 0x1D, 2, 0);
      });
      _keyEvent(0x11, 0x1D, 2, 0);
      final directory = await Directory.systemTemp.createTemp(
        'skysecret-presentation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final desktop = DesktopController(
        settings: ShortcutStore(file: File('${directory.path}/settings.json')),
      );
      addTearDown(desktop.releaseResources);
      await LocaleSettings.setLocale(AppLocale.ru);
      const capture = Key('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: SkySecretApp(desktop: desktop),
        ),
      );
      await desktop.initialize();
      await desktop.show();
      await tester.pumpAndSettle();
      final expected =
          await calcWindowPosition(
            await windowManager.getSize(),
            Alignment.bottomRight,
          ) -
          const Offset(12, 12);
      final actual = await windowManager.getPosition();
      expect((actual - expected).distance, lessThan(2));
      expect(find.text('Shift + Space'), findsOneWidget);

      Future<void> screenshot(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/qa')..createSync(recursive: true);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      }

      for (final locale in AppLocale.values) {
        await LocaleSettings.setLocale(locale);
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.generator));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(
          find.byKey(const Key('length-slider')),
        );
        slider.onChanged!(64);
        slider.onChangeEnd!(64);
        await tester.pumpAndSettle();
        for (final size in [const Size(460, 600), const Size(400, 520)]) {
          await windowManager.setSize(size);
          await tester.pumpAndSettle();
          expectPasswordFullyVisible(tester);
          final content = find.byKey(const Key('manager-content'));
          final scroll = find
              .descendant(of: content, matching: find.byType(Scrollable))
              .first;
          expect(
            tester.state<ScrollableState>(scroll).position.maxScrollExtent,
            0,
          );
          final footer = tester.getRect(
            find.byKey(const Key('manager-footer')),
          );
          expect(
            tester.getRect(find.byKey(const Key('clipboard-help'))).bottom,
            lessThan(footer.top),
          );
          expect(
            find.byKey(const Key('copy-password')).hitTestable(),
            findsOneWidget,
          );
          await screenshot('generator-${locale.name}-${size.width.toInt()}');
        }
      }
      await LocaleSettings.setLocale(AppLocale.ru);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-settings')));
      await tester.pumpAndSettle();
      expect(find.text(t.shortcutListening), findsOneWidget);
      await windowManager.focus();
      await tester.runAsync(() async {
        _keyEvent(0x11, 0x1D, 0, 0);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
      expect(find.text('Ctrl + …'), findsOneWidget);
      try {
        await tester.runAsync(() async {
          _keyEvent(0x77, 0x42, 0, 0);
          await Future<void>.delayed(const Duration(milliseconds: 120));
          _keyEvent(0x77, 0x42, 2, 0);
        });
      } finally {
        _keyEvent(0x11, 0x1D, 2, 0);
      }
      await tester.pumpAndSettle();
      expect(find.text('Ctrl + F8'), findsOneWidget);
      await screenshot('shortcut-recorder');
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(find.text('Ctrl + F8'), findsOneWidget);
      expect(shortcutLabel(desktop.shortcut), 'Ctrl + F8');
      await desktop.hide();
      await windowManager.setPosition(const Offset(100, 100));
      await desktop.show();
      final reopened = await windowManager.getPosition();
      final corner =
          await calcWindowPosition(
            await windowManager.getSize(),
            Alignment.bottomRight,
          ) -
          const Offset(12, 12);
      expect((reopened - corner).distance, lessThan(2));
      expect(tester.takeException(), isNull);
      await desktop.releaseResources();
    },
  );
}
