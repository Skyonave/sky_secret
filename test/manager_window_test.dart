import 'dart:io';

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

import 'support/password_preview_assertions.dart';

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
    await tester.tap(find.text(t.generator));
    await tester.pumpAndSettle();
  }

  Future<void> copy(WidgetTester tester) async {
    final button = find.byKey(const Key('copy-password'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  String password(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('generated-password'))).data!;

  testWidgets('empty state, generator, Escape and close hide', (tester) async {
    final desktop = FakeDesktop();
    await open(tester, desktop);
    expect(find.text(t.emptyVault), findsOneWidget);
    await generator(tester);
    expect(password(tester).length, 24);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(desktop.hides, 1);
    await tester.tap(find.byTooltip(t.hide));
    expect(desktop.hides, 2);
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocale.values) {
    for (final size in [
      const Size(460, 600),
      const Size(444, 584),
      const Size(400, 520),
      const Size(384, 504),
    ]) {
      testWidgets('generator fits without scrolling: ${locale.name} $size', (
        tester,
      ) async {
        await LocaleSettings.setLocale(locale);
        await open(tester, FakeDesktop(), size: size);
        await generator(tester);
        final content = find.byKey(const Key('manager-content'));
        final scrollable = find.descendant(of: content, matching: find.byType(Scrollable)).first;
        for (final length in [24.0, 64.0, 12.0]) {
          final slider = tester.widget<Slider>(
            find.byKey(const Key('length-slider')),
          );
          slider.onChanged!(length);
          slider.onChangeEnd!(length);
          await tester.pump();
          expectPasswordFullyVisible(tester);
          expect(
            tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
            0,
          );
          final viewport = tester.getRect(content);
          for (final key in [
            'password-panel',
            'length-slider',
            'copy-password',
            'clipboard-help',
          ]) {
            final rect = tester.getRect(find.byKey(Key(key)));
            expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: key);
            expect(
              rect.bottom,
              lessThanOrEqualTo(viewport.bottom),
              reason: key,
            );
          }
          expect(
            find.byKey(const Key('copy-password')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
    testWidgets('stable slider layout and translations: ${locale.name}', (
      tester,
    ) async {
      await LocaleSettings.setLocale(locale);
      await open(tester, FakeDesktop(), size: const Size(400, 520));
      expect(find.text(t.emptyVault), findsOneWidget);
      expect(
        find.text(locale == AppLocale.ru ? 'Сейф' : 'Vault'),
        findsOneWidget,
      );
      await generator(tester);
      final slider = find.byKey(const Key('length-slider'));
      final panel = find.byKey(const Key('password-panel'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final initialPanel = tester.getRect(panel);
      final initialSlider = tester.getRect(slider);
      final initialPassword = password(tester);
      for (final length in [12.0, 35.0, 64.0]) {
        tester.widget<Slider>(slider).onChanged!(length);
        await tester.pump();
        expect(password(tester), initialPassword);
        expect(tester.getRect(panel), initialPanel);
        expect(tester.getRect(slider), initialSlider);
      }
      tester.widget<Slider>(slider).onChangeEnd!(64);
      await tester.pump();
      expect(password(tester).length, 64);
      expect(tester.getRect(panel), initialPanel);
      expect(tester.getRect(slider), initialSlider);
      expect(tester.takeException(), isNull);
    });
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
        await tester.pump(const Duration(seconds: 31));
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
    await tester.pump(const Duration(seconds: 20));
    await copy(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(clipboard.text, isNotNull);
    clipboard.failures = 1;
    await tester.pump(const Duration(seconds: 10));
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
