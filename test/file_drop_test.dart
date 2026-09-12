import 'dart:async';
import 'dart:io';

import 'package:skysecret/ui/shared/native_file_drop_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/desktop/focus_dismissal.dart';
import 'package:skysecret/i18n/translations.g.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;
import 'vault_organization_ui_test.dart' show OrganizationStore;

class DropDesktop extends FakeDesktop {
  bool hovering = false;
  int accepted = 0;
  @override
  void setFileDragHover(bool value) => hovering = value;
  @override
  Future<bool> focusFileDrop() async {
    accepted++;
    return true;
  }
}

void main() {
  testWidgets(
    'blur keeps a held drag, releases outside, cancels on other buttons; stale reads cannot hide',
    (tester) async {
      var left = true;
      var over = false;
      var protected = false;
      var cancel = false;
      var hides = 0;
      final guard = FocusDismissal(
        readState: () async => (
          protectedFocus: protected,
          leftDown: left,
          cancelDrag: cancel,
          fileOver: over,
        ),
        dismiss: () async {
          hides++;
        },
      );
      addTearDown(guard.cancel);
      guard.request();
      await tester.pump(const Duration(seconds: 2));
      expect(hides, 0);
      left = false;
      await tester.pump(const Duration(milliseconds: 50));
      expect(hides, 1);
      left = true;
      guard.request();
      await tester.pump();
      cancel = true;
      await tester.pump(const Duration(milliseconds: 50));
      expect(hides, 2);
      cancel = false;
      over = true;
      guard.request();
      await tester.pump();
      left = false;
      await tester.pump(const Duration(milliseconds: 50));
      expect(hides, 2);
      guard.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(hides, 2);
      guard.request();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(hides, 3);
      protected = true;
      guard.request();
      await tester.pump();
      expect(hides, 3);
      final pending = Completer<DismissalState>();
      final stale = FocusDismissal(
        readState: () => pending.future,
        dismiss: () async {
          hides++;
        },
      );
      stale.request();
      stale.cancel();
      pending.complete((
        protectedFocus: false,
        leftDown: false,
        cancelDrag: false,
        fileOver: false,
      ));
      await tester.pump();
      expect(hides, 3);
    },
  );

  for (final locale in AppLocale.values) {
    testWidgets(
      'drop batch, rejection, locked vault and modal: ${locale.name}',
      (tester) async {
        await LocaleSettings.setLocale(locale);
        final session = (await tester.runAsync(
          () => VaultCipher.create('Synthetic master 1!'),
        ))!;
        final store = OrganizationStore(session);
        final desktop = DropDesktop();
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('sm-drop-widget-'),
        ))!;
        addTearDown(() => dir.delete(recursive: true));
        addTearDown(session.lock);
        final one = File('${dir.path}/пример.txt');
        final two = File('${dir.path}/synthetic.bin');
        await tester.runAsync(() async {
          await one.writeAsString('Synthetic text');
          await two.writeAsBytes([0, 255, 12, 42]);
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 520);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          SkySecretApp(
            desktop: desktop,
            clipboard: FakeClipboard(),
            vaultStore: store,
          ),
        );
        await tester.pumpAndSettle();

        Future<void> drop(List<String> paths, {bool locked = false}) async {
          final target = tester.widget<NativeFileDropTarget>(
            find.byKey(const Key('vault-file-drop')),
          );
          target.onHover(true);
          await tester.pump();
          expect(
            find.byKey(const Key('vault-file-drop-overlay')),
            locked ? findsOneWidget : findsNothing,
          );
          expect(desktop.hovering, isTrue);
          await tester.runAsync(() async {
            target.onFiles(paths);
            for (var i = 0; i < 30; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();
          expect(desktop.hovering, isFalse);
          expect(
            find.byKey(const Key('vault-file-drop-overlay')),
            findsNothing,
          );
        }

        await drop([one.path], locked: true);
        expect(session.entries, isEmpty);
        expect(find.text(t.vaultDropLocked), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('vault-master')),
          'Synthetic master 1!',
        );
        await tester.tap(find.byKey(const Key('open-vault')));
        await tester.pumpAndSettle();
        await drop([one.path, two.path, one.path]);
        expect(session.entries.length, 2);
        expect(
          session.entries.every((e) => e.isFile && e.folderId == null),
          isTrue,
        );
        expect(session.entries.last.attachments.single.bytes, [0, 255, 12, 42]);
        await drop([one.path, dir.path]);
        expect(session.entries.length, 2);
        expect(find.text(t.vaultDropFilesOnly), findsOneWidget);
        store.failNext = true;
        await drop([one.path]);
        expect(session.entries.length, 2);
        await tester.tap(find.byKey(const Key('vault-settings')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NativeFileDropTarget>(
                find.byKey(const Key('vault-file-drop')),
              )
              .enable,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
