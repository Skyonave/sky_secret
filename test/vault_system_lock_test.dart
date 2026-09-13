import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;
import 'vault_organization_ui_test.dart' show OrganizationStore;

class GatedUnlockStore extends OrganizationStore {
  GatedUnlockStore(super.session);
  final gate = Completer<void>();
  @override
  Future<VaultSession> unlock(String password) async {
    await gate.future;
    return session;
  }
}

void main() {
  testWidgets(
    'system lock cancels pending unlock and clears entered credentials',
    (tester) async {
      final session = (await tester.runAsync(
        () => VaultCipher.create('Synthetic password 1!'),
      ))!;
      final store = GatedUnlockStore(session);
      await tester.pumpWidget(
        SkySecretApp(
          desktop: FakeDesktop(),
          clipboard: FakeClipboard(),
          vaultStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Synthetic password 1!',
      );
      await tester.tap(find.byKey(const Key('open-vault')));
      await tester.pump();
      final delivered = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'skysecret/system_lock',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('lock')),
        (_) => delivered.complete(),
      );
      await delivered.future;
      store.gate.complete();
      await tester.pumpAndSettle();
      expect(session.isLocked, isTrue);
      expect(find.byKey(const Key('lock-vault')), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vault-master'))).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
