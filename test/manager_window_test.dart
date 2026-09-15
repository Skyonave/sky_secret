import 'dart:io';
import 'dart:async';

import 'package:skysecret/ui/generator/generator_dialog.dart';
import 'package:skysecret/ui/generator/generator_service.dart';
import 'package:skysecret/core/settings/generator_preferences.dart';
import 'package:skysecret/ui/vault/vault_panel.dart';
import 'package:skysecret/ui/shared/input/sensitive_text_editing.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/desktop_actions.dart';
import 'package:skysecret/core/desktop/clipboard/sensitive_clipboard.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';
import 'package:skysecret/i18n/translations.g.dart';

class EmptyTestVaultStore extends VaultStore {
  EmptyTestVaultStore() : super(file: File('unused-widget-test-vault'));
  @override
  Future<bool> exists() async => false;
}

class FakeDesktop extends DesktopActions {
  int hides = 0;
  bool capturing = false;
  String? saveError;
  @override
  String? notice;
  @override
  HotKey shortcut = defaultShortcut();
  @override
  void setShortcutCapture(bool capturing) => this.capturing = capturing;
  @override
  Future<String?> updateShortcut(HotKey value) async {
    if (saveError != null) return saveError;
    shortcut = value;
    notifyListeners();
    return null;
  }

  @override
  Future<void> hide() async {
    hides++;
  }

  @override
  Future<void> drag() async {}
}

class FakeClipboard implements SensitiveClipboard {
  String? text;
  int revision = 0;
  int failures = 0;
  @override
  Future<int> write(String value) async {
    text = value;
    return ++revision;
  }

  @override
  Future<bool> clearIfCurrent(int owned) async {
    if (failures > 0) {
      failures--;
      throw const ClipboardUnavailable();
    }
    if (owned != revision) return false;
    text = null;
    revision++;
    return true;
  }
}

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.ru);
  });
  Future<void> open(
    WidgetTester tester,
    FakeDesktop desktop, {
    Size size = const Size(460, 600),
    FakeClipboard? clipboard,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SkySecretApp(
        desktop: desktop,
        clipboard: clipboard ?? FakeClipboard(),
        vaultStore: EmptyTestVaultStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> generator(WidgetTester tester) async {
    expect(find.byKey(const Key('open-generator')), findsNothing);
    final context = tester.element(find.byType(VaultPanel));
    unawaited(
      showGenerator(
        context: context,
        service: GeneratorService(GeneratorPreferences()),
        copy: (value) => SensitiveClipboardScope.copyText(context, value),
        actionLabel: t.generatorUseEntry,
        canApply: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> copy(WidgetTester tester) async {
    final button = find.byKey(const Key('generator-copy'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  String password(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('generated-password'))).data!;

  testWidgets('generator Escape closes the panel, manager close hides', (tester) async {
    final desktop = FakeDesktop();
    await open(tester, desktop);
    expect(find.text(t.emptyVault), findsOneWidget);
    await generator(tester);
    expect(password(tester).length, 24);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(desktop.hides, 0);
    await tester.tap(find.byTooltip(t.hide));
    expect(desktop.hides, 1);
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocale.values) {
    for (final size in [const Size(460, 600), const Size(384, 504)]) {
      testWidgets('generator numeric settings remain usable: ${locale.name} $size', (tester) async {
        await LocaleSettings.setLocale(locale);
        await open(tester, FakeDesktop(), size: size);
        await generator(tester);
        final count = find.byKey(const Key('generator-count'));
        for (final length in [12, 64, 24]) {
          await tester.ensureVisible(count);
          await tester.enterText(count, '$length');
          await tester.pumpAndSettle();
          expect(password(tester).length, length);
          await tester.ensureVisible(find.byKey(const Key('generator-copy')));
          expect(find.byKey(const Key('generator-copy')).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final externalCopy in [false, true]) {
    testWidgets(
      'clipboard expiry preserves newer copies, even identical: $externalCopy',
      (tester) async {
        final clipboard = FakeClipboard();
        await open(tester, FakeDesktop(), clipboard: clipboard);
        await generator(tester);
        await copy(tester);
        expect(clipboard.text, isNotEmpty);
        if (externalCopy) clipboard.revision++;
        await tester.pump(const Duration(seconds: 11));
        expect(clipboard.text == null, !externalCopy);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('busy clipboard retries cleanup and recopy restarts timer', (
    tester,
  ) async {
    final clipboard = FakeClipboard();
    await open(tester, FakeDesktop(), clipboard: clipboard);
    await generator(tester);
    await copy(tester);
    await tester.pump(const Duration(seconds: 6));
    await copy(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(clipboard.text, isNotNull);
    clipboard.failures = 1;
    await tester.pump(const Duration(seconds: 4));
    expect(clipboard.text, isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard.text, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shortcut recorder saves, reports conflicts and cancels', (
    tester,
  ) async {
    final desktop = FakeDesktop();
    await open(tester, desktop);
    await tester.tap(find.byKey(const Key('shortcut-settings')));
    await tester.pumpAndSettle();
    expect(desktop.capturing, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Ctrl + …'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, t.save)).onPressed,
      isNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text('Ctrl + Alt + …'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Ctrl + Alt + K'), findsOneWidget);
    desktop.saveError = t.shortcutBusy;
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(find.text(t.shortcutBusy), findsOneWidget);
    expect(sameShortcut(desktop.shortcut, defaultShortcut()), isTrue);
    desktop.saveError = null;
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(desktop.capturing, isFalse);
    expect(shortcutLabel(desktop.shortcut), 'Ctrl + Alt + K');
    await tester.tap(find.byKey(const Key('shortcut-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.resetShortcut));
    await tester.tap(find.text(t.cancel));
    await tester.pumpAndSettle();
    expect(shortcutLabel(desktop.shortcut), 'Ctrl + Alt + K');
    expect(desktop.capturing, isFalse);
    expect(tester.takeException(), isNull);
  });
}
