import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/desktop/desktop_controller.dart';
import 'package:skysecret/desktop/shortcut_settings.dart';
import 'package:skysecret/desktop/windows_sensitive_clipboard.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:win32/win32.dart' as win32;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final _keyEvent = DynamicLibrary.open('user32.dll')
    .lookupFunction<
      Void Function(Uint8, Uint8, Uint32, UintPtr),
      void Function(int, int, int, int)
    >('keybd_event');

Future<void> shortcut({bool hold = false}) async {
  _keyEvent(0x10, 0, 0, 0);
  _keyEvent(0x20, 0, 0, 0);
  try {
    await Future<void>.delayed(Duration(milliseconds: hold ? 1200 : 150));
  } finally {
    _keyEvent(0x20, 0, 2, 0);
    _keyEvent(0x10, 0, 2, 0);
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows tray lifecycle and real global Shift+Space', (
    tester,
  ) async {
    await LocaleSettings.setLocale(AppLocale.ru);
    final directory = await Directory.systemTemp.createTemp(
      'skysecret-native-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = ShortcutStore(file: File('${directory.path}/settings.json'));
    final desktop = DesktopController(settings: store);
    addTearDown(desktop.releaseResources);
    const captureKey = Key('capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: SkySecretApp(
          desktop: desktop,
          vaultCatalog: VaultCatalog(directory: directory),
        ),
      ),
    );
    await desktop.initialize();
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isFalse,
      reason: 'No startup window',
    );
    expect(await windowManager.isSkipTaskbar(), isTrue);
    expect(await windowManager.isPreventClose(), isTrue);
    expect(
      desktop.notice,
      isNull,
      reason: 'The test requires a free Shift+Space',
    );
    final trayBounds = await trayManager.getBounds();
    expect(trayBounds, isNotNull);

    await tester.runAsync(() => shortcut(hold: true));
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isTrue,
      reason: 'Shortcut opens once while held',
    );
    expect(await windowManager.isFocused(), isTrue);
    expect(find.text('Сейф ещё не создан'), findsOneWidget);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('build/qa')..createSync(recursive: true);
    File('${output.path}/manager.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();

    await tester.runAsync(() => shortcut());
    await tester.pumpAndSettle();
    expect(await windowManager.isVisible(), isFalse, reason: 'Shortcut hides');
    desktop.onTrayIconMouseDown();
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isTrue,
      reason: 'Tray action opens',
    );
    await tester.tap(find.byKey(const Key('shortcut-settings')));
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isTrue,
      reason: 'Focusing a control/dialog does not hide the native window',
    );
    await windowManager.blur();
    for (var i = 0; i < 40 && await windowManager.isVisible(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      await windowManager.isVisible(),
      isFalse,
      reason: 'Losing native focus hides the window',
    );
    await tester.runAsync(() => shortcut());
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isTrue,
      reason: 'Hotkey reopens even when shortcut settings were left open',
    );
    expect(find.text(t.shortcutTitle), findsOneWidget);
    await tester.tap(find.text(t.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Скрыть в трей · Esc'));
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isFalse,
      reason: 'Close button hides',
    );
    await desktop.show();
    await windowManager.close();
    for (var i = 0; i < 40 && await windowManager.isVisible(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      await windowManager.isVisible(),
      isFalse,
      reason: 'Native close hides',
    );

    final clipboard = WindowsSensitiveClipboard();
    final firstRevision = await clipboard.write('synthetic clipboard fixture');
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      'synthetic clipboard fixture',
    );
    for (final name in WindowsSensitiveClipboard.privacyFormats) {
      final native = name.toPcwstr();
      final format = win32.RegisterClipboardFormat(native).value;
      win32.free(native);
      expect(win32.IsClipboardFormatAvailable(format).value, isTrue);
      var opened = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        if (win32.OpenClipboard(null).value) {
          opened = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(opened, isTrue, reason: 'Clipboard inspection lock');
      try {
        final handle = win32.GetClipboardData(format).value;
        final memory = win32.HGLOBAL(handle);
        final data = win32.GlobalLock(memory).value;
        expect(data, isNot(nullptr));
        try {
          expect(data.cast<Uint32>().value, 0);
        } finally {
          win32.GlobalUnlock(memory);
        }
      } finally {
        win32.CloseClipboard();
      }
    }
    expect(
      await clipboard.clearIfCurrent(firstRevision),
      isTrue,
      reason: 'Reading text does not prevent expiry',
    );
    final secondRevision = await clipboard.write('synthetic clipboard fixture');
    expect(await clipboard.clearIfCurrent(firstRevision), isFalse);
    expect(await clipboard.clearIfCurrent(secondRevision), isTrue);
    expect(
      win32.IsClipboardFormatAvailable(win32.CF_UNICODETEXT).value,
      isFalse,
    );

    final candidate = HotKey(
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    );
    expect(await desktop.updateShortcut(candidate), isNull);
    expect(sameShortcut((await store.load())!, candidate), isTrue);
    final blocker = HotKey(
      key: PhysicalKeyboardKey.keyJ,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    );
    await hotKeyManager.register(blocker);
    try {
      expect(await desktop.updateShortcut(blocker), t.shortcutBusy);
      expect(sameShortcut(desktop.shortcut, candidate), isTrue);
    } finally {
      await hotKeyManager.unregister(blocker);
    }
    await desktop.hide();
    expect(await windowManager.isVisible(), isFalse);
    await tester.runAsync(() async {
      _keyEvent(0x11, 0, 0, 0);
      _keyEvent(0x12, 0, 0, 0);
      _keyEvent(0x4B, 0, 0, 0);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } finally {
        _keyEvent(0x4B, 0, 2, 0);
        _keyEvent(0x12, 0, 2, 0);
        _keyEvent(0x11, 0, 2, 0);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(
      await windowManager.isVisible(),
      isTrue,
      reason: 'Custom shortcut opens',
    );

    await desktop.releaseResources();
    expect(tester.takeException(), isNull);
  });
}
