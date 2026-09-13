import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/os/windows/desktop_controller.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import '../test/manager_window_test.dart' show FakeClipboard;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native file drop channel and encrypted batch on Windows', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('sm-native-drop-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final seed = await store.create('Synthetic drop password');
    seed.lock();
    final source = File('${directory.path}/пример.txt');
    final binary = File('${directory.path}/synthetic.bin');
    await source.writeAsString('Synthetic drag-and-drop text');
    await binary.writeAsBytes([0, 42, 255, 128]);
    final desktop = DesktopController(
      settings: ShortcutStore(file: File('${directory.path}/keys.json')),
    );
    addTearDown(desktop.releaseResources);
    const capture = Key('drop-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: SkySecretApp(
          desktop: desktop,
          clipboard: FakeClipboard(),
          vaultStore: store,
          vaultPreferences: VaultPreferences(
            file: File('${directory.path}/prefs.json'),
          ),
        ),
      ),
    );
    await desktop.initialize();
    await desktop.show();
    await windowManager.setSize(const Size(400, 520));
    await tester.pumpAndSettle();
    expect(
      await const MethodChannel('skysecret/file_drop')
          .invokeMethod<bool>('ready'),
      isTrue,
    );
    Future<void> emit(String method, [List<String> paths = const []]) async {
      final done = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'skysecret/file_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, paths)),
        (_) => done.complete(),
      );
      await done.future;
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.byKey(const Key('vault-master')),
      'Synthetic drop password',
    );
    await tester.tap(find.byKey(const Key('open-vault')));
    await tester.pumpAndSettle();
    for (final locale in AppLocale.values) {
      await LocaleSettings.setLocale(locale);
      await emit('entered');
      expect(find.text(t.vaultDropHint), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary
          .toImage(pixelRatio: 1)
          .timeout(const Duration(seconds: 10));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File('build/qa/file-drop-${locale.name}-400.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      await emit('exited');
    }
    final windowId = await const MethodChannel('window_manager')
        .invokeMethod<int>('getId');
    final delivery = await Process.start(
      'build/native_drop_tests/Debug/native_drop_tests.exe',
      [windowId.toString(), source.path],
    );
      final int deliveryExit;
      final output = delivery.stdout.transform(const SystemEncoding().decoder).join();
    try {
      deliveryExit = await delivery.exitCode.timeout(
        const Duration(seconds: 8),
      );
    } finally {
      delivery.kill();
    }
    expect(
      deliveryExit,
      0,
        reason: 'Synthetic source must complete a real OLE COPY: ${await output}',
    );
    await tester.pumpAndSettle();
    await emit('entered');
    await emit('files', [binary.path]);
    expect(find.text('пример.txt'), findsOneWidget);
    expect(find.text('synthetic.bin'), findsOneWidget);
    final reopened = await store.unlock('Synthetic drop password');
    expect(reopened.entries.length, 2);
    expect(reopened.entries.every((e) => e.isFile), isTrue);
    expect(
      reopened.entries.last.attachments.single.bytes,
      await binary.readAsBytes(),
    );
    reopened.lock();
    final before = await store.file.readAsBytes();
    await emit('entered');
    await emit('files', [source.path, directory.path]);
    expect(await store.file.readAsBytes(), before);
    expect(find.text(t.vaultDropFilesOnly), findsOneWidget);
    final large = File('${directory.path}/too-large.bin');
    final handle = await large.open(mode: FileMode.write);
    await handle.truncate(VaultCipher.maxAttachmentBytes + 1);
    await handle.close();
    await emit('entered');
    await emit('files', [source.path, large.path]);
    expect(await store.file.readAsBytes(), before);
    expect(find.text(t.vaultAttachmentLimit), findsOneWidget);
    await tester.tap(find.byKey(const Key('lock-vault')));
    await tester.pumpAndSettle();
    await emit('entered');
    await emit('files', [source.path]);
    expect(await store.file.readAsBytes(), before);
    expect(find.text(t.vaultDropLocked), findsOneWidget);
    expect(await source.readAsString(), 'Synthetic drag-and-drop text');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
