import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;
import 'vault_organization_ui_test.dart' show OrganizationStore;

class PausedStore extends OrganizationStore {
  PausedStore(super.session);
  Completer<void>? gate;
  @override
  Future<void> save(
    VaultSession session,
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    await gate?.future;
    if (!session.isLocked) {
      await super.save(session, entries, folders: folders, name: name);
    }
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    OrganizationStore store, {
    VaultPreferences? preferences,
  }) async {
    await LocaleSettings.setLocale(AppLocale.ru);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(384, 504);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SkySecretApp(
        desktop: FakeDesktop(),
        clipboard: FakeClipboard(),
        vaultStore: store,
        vaultPreferences: preferences,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vault-master')),
      'Synthetic password 1!',
    );
    await tester.tap(find.byKey(const Key('open-vault')));
    await tester.pumpAndSettle();
  }

  testWidgets('disable stops timeout and reenable starts a fresh timeout', (
    tester,
  ) async {
    final session = (await tester.runAsync(
      () => VaultCipher.create('Synthetic password 1!'),
    ))!;
    final preferences = VaultPreferences();
    await mount(tester, OrganizationStore(session), preferences: preferences);
    Future<void> configure(bool enabled) async {
      await tester.tap(find.byKey(const Key('vault-settings')));
      await tester.pumpAndSettle();
      tester.widget<SwitchListTile>(find.byKey(const Key('auto-lock-switch'))).onChanged!(enabled);
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-vault-preferences')));
      await tester.pumpAndSettle();
    }

    await configure(false);
    expect(await preferences.loadAutoLock(), isFalse);
    await tester.pump(const Duration(minutes: 5));
    expect(session.isLocked, isFalse);
    await configure(true);
    expect(await preferences.loadAutoLock(), isTrue);
    await tester.pump(const Duration(seconds: 119));
    expect(session.isLocked, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(session.isLocked, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'password count, configurable generation and cancel preserve draft',
    (tester) async {
      final session = (await tester.runAsync(
        () => VaultCipher.create('Synthetic password 1!'),
      ))!;
      await mount(tester, OrganizationStore(session));
      await tester.tap(find.byKey(const Key('add-entry')));
      await tester.pumpAndSettle();
      String password() => tester.widget<TextField>(find.byKey(const Key('entry-password'))).controller!.text;
      expect(password().length, 24);
      expect(find.text(t.vaultPasswordLength(length: 24)), findsOneWidget);
      final original = password();
      await tester.tap(find.byKey(const Key('entry-password-options')));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byKey(const Key('entry-length-slider'))).onChanged!(48);
      tester.widget<SwitchListTile>(find.byKey(const Key('entry-symbols-switch'))).onChanged!(false);
      await tester.pump();
      await tester.tap(find.text(t.cancel).last);
      await tester.pumpAndSettle();
      expect(password(), original);
      await tester.tap(find.byKey(const Key('entry-password-options')));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byKey(const Key('entry-length-slider'))).onChanged!(48);
      tester.widget<SwitchListTile>(find.byKey(const Key('entry-symbols-switch'))).onChanged!(false);
      await tester.pump();
      await tester.tap(find.byKey(const Key('apply-password-options')));
      await tester.pumpAndSettle();
      expect(password(), matches(RegExp(r'^[a-zA-Z0-9]{48}$')));
      expect(find.text(t.vaultPasswordLength(length: 48)), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('entry-password')),
        'Synthetic manual value',
      );
      await tester.pump();
      expect(find.text(t.vaultPasswordLength(length: 22)), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'activity resets two-minute timeout; hidden vault and modal lock',
    (tester) async {
      final session = (await tester.runAsync(
        () => VaultCipher.create('Synthetic password 1!'),
      ))!;
      await mount(tester, OrganizationStore(session));
      await tester.pump(const Duration(seconds: 100));
      expect(session.isLocked, isFalse);
      await tester.tap(find.byKey(const Key('add-folder')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vault-name-input')),
        'Unsaved synthetic section',
      );
      await tester.pump(const Duration(seconds: 100));
      expect(session.isLocked, isFalse);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(session.isLocked, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(t.vaultLocked), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      final hidden = (await tester.runAsync(
        () => VaultCipher.create('Synthetic password 1!'),
      ))!;
      await mount(tester, OrganizationStore(hidden));
      await tester.tap(find.text(t.generator));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(hidden.isLocked, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('timeout during save cannot reopen vault when write completes', (
    tester,
  ) async {
    final session = (await tester.runAsync(
      () => VaultCipher.create('Synthetic password 1!'),
    ))!;
    final store = PausedStore(session);
    await mount(tester, store);
    await tester.tap(find.byKey(const Key('add-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('entry-title')),
      'Synthetic draft',
    );
    store.gate = Completer<void>();
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(session.isLocked, isTrue);
    expect(find.text(t.vaultLocked), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(t.vaultLocked), findsOneWidget);
    expect(find.text('Synthetic draft'), findsNothing);
    expect(find.text(t.vaultWriteFailed), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
