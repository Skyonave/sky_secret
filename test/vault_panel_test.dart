import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/i18n/translations.g.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;

class DelayedClipboard extends FakeClipboard {
  Completer<void>? gate;
  @override
  Future<int> write(String value) async {
    await gate?.future;
    return super.write(value);
  }
}

class ObservedStore extends VaultStore {
  ObservedStore(File file) : super(file: file);
  Future<VaultSession>? opening;
  Future<void>? saving;
  @override
  Future<VaultSession> create(String password, {String? name}) =>
      opening = super.create(password, name: name);
  @override
  Future<VaultSession> unlock(String password) =>
      opening = super.unlock(password);
  @override
  Future<void> save(
    VaultSession session,
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) => saving = super.save(session, entries, folders: folders, name: name);
}

void main() {
  for (final locale in AppLocale.values) {
    testWidgets(
      'vault UI create/save/restart/unlock/edit/copy/lock: ${locale.name}',
      (tester) async {
        await LocaleSettings.setLocale(locale);
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('sm-vault-ui-test-'),
        ))!;
        addTearDown(() => directory.delete(recursive: true));
        final store = ObservedStore(File('${directory.path}/vault.smv'));
        final clipboard = DelayedClipboard();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(384, 504);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<void> mount() async {
          await tester.runAsync(() async {
            await tester.pumpWidget(
              SkySecretApp(
                desktop: FakeDesktop(),
                clipboard: clipboard,
                vaultStore: store,
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final button = find.byKey(Key(key));
          await tester.ensureVisible(button);
          await tester.tap(button);
        }

        Future<void> open() async {
          await tester.runAsync(() async {
            await tap('open-vault');
            await store.opening;
          });
          await tester.pumpAndSettle();
        }

        Future<void> save() async {
          await tester.runAsync(() async {
            await tap('save-entry');
            await store.saving;
          });
          await tester.pumpAndSettle();
        }

        await mount();
        expect(find.text(t.emptyVault), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('vault-master')),
          'Synthetic UI phrase 1!',
        );
        await tester.enterText(
          find.byKey(const Key('vault-confirm')),
          'mismatch',
        );
        await tap('open-vault');
        await tester.pumpAndSettle();
        expect(find.text(t.vaultPasswordMismatch), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('vault-confirm')),
          'Synthetic UI phrase 1!',
        );
        await open();
        await tap('add-entry');
        await tester.pumpAndSettle();
        final generated = tester
            .widget<TextField>(find.byKey(const Key('entry-password')))
            .controller!
            .text;
        expect(generated.length, 24);
        await tester.tap(find.byKey(const Key('generate-entry-password')));
        await tester.pump();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('entry-password')))
              .controller!
              .text,
          isNot(generated),
        );
        await tester.enterText(
          find.byKey(const Key('entry-title')),
          'Synthetic UI record',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => switch (call.method) {
            'Clipboard.getData' => {'text': 'Synthetic UI secret'},
            'Clipboard.hasStrings' => {'value': true},
            _ => null,
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.tap(find.byKey(const Key('entry-password')));
        await tester.pump();
        final passwordField = tester.state<EditableTextState>(
          find.descendant(
            of: find.byKey(const Key('entry-password')),
            matching: find.byType(EditableText),
          ),
        );
        passwordField.widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: passwordField.widget.controller.text.length,
        );
        await passwordField.pasteText(SelectionChangedCause.keyboard);
        await tester.pump();
        expect(passwordField.widget.controller.text, 'Synthetic UI secret');
        passwordField.widget.controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 19,
        );
        expect(
          passwordField.copyEnabled,
          isFalse,
        );
        await save();
        expect(find.text('Synthetic UI record'), findsOneWidget);
        expect(find.text('Synthetic UI secret'), findsNothing);
        await tester.pumpWidget(
          const SizedBox.shrink(),
        );
        await mount();
        expect(find.text(t.vaultLocked), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('vault-master')),
          'Synthetic UI phrase 1!',
        );
        await open();
        expect(find.text('Synthetic UI record'), findsOneWidget);
        await tester.tap(find.text('Synthetic UI record'));
        await tester.pumpAndSettle();
        expect(clipboard.text, 'Synthetic UI secret');
        await tester.tap(find.byTooltip(t.vaultEditEntry));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('entry-title')),
          'Updated synthetic record',
        );
        await save();
        expect(find.text('Updated synthetic record'), findsOneWidget);
        clipboard.gate = Completer<void>();
        await tester.tap(find.text('Updated synthetic record'));
        await tester.pump();
        await tap('lock-vault');
        await tester.pumpAndSettle();
        expect(find.text(t.vaultLocked), findsOneWidget);
        expect(find.text('Updated synthetic record'), findsNothing);
        expect(clipboard.text, isNull);
        clipboard.gate!.complete();
        await tester.pumpAndSettle();
        expect(
          clipboard.text,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
