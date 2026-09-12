import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:skysecret/ui/editor/file_editor_window.dart';

import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/desktop/desktop_controller.dart';
import 'package:skysecret/desktop/shortcut_settings.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

import '../test/manager_window_test.dart' show FakeClipboard;

win32.HWND ownRunnerWindow() {
  final user = DynamicLibrary.open('user32.dll');
  final enumerate = user
      .lookupFunction<
        Int32 Function(
          Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>,
          IntPtr,
        ),
        int Function(
          Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>,
          int,
        )
      >('EnumWindows');
  final className = user
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Int32),
        int Function(int, Pointer<Utf16>, int)
      >('GetClassNameW');
  var found = 0;
  final callback = NativeCallable<Int32 Function(IntPtr, IntPtr)>.isolateLocal((
    int id,
    int _,
  ) {
    return using((arena) {
      final owner = arena<Uint32>();
      win32.GetWindowThreadProcessId(
        win32.HWND(Pointer.fromAddress(id)),
        owner,
      );
      final name = arena<Uint16>(256).cast<Utf16>();
      className(id, name, 256);
      if (owner.value == win32.GetCurrentProcessId() &&
          name.toDartString() == 'FLUTTER_RUNNER_WIN32_WINDOW') {
        found = id;
        return 0;
      }
      return 1;
    });
  }, exceptionalReturn: 0);
  try {
    enumerate(callback.nativeFunction, 0);
  } finally {
    callback.close();
  }
  expect(found, isNonZero);
  return win32.HWND(Pointer.fromAddress(found));
}

class SyntheticPicker extends FileSelectorPlatform {
  String? openPath;
  String? savePath;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => openPath == null ? null : XFile(openPath!);
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => savePath == null ? null : FileSaveLocation(savePath!);
}

Future<void> exerciseEditorWindow() async {
  const report = WindowMethodChannel(
    'skysecret/test-editor-report',
    mode: ChannelMode.unidirectional,
  );
  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Synthetic editor timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  try {
    final mode = await report.invokeMethod<String>('scenario');
    await waitFor(() => WidgetsBinding.instance.rootElement != null);
    await waitFor(
      () => find.byKey(const Key('file-editor-text')).evaluate().isNotEmpty,
    );
    final field =
        find.byKey(const Key('file-editor-text')).evaluate().single.widget
            as TextField;
    final initial = mode == 'lock'
        ? 'Synthetic original\ntext'
        : 'Synthetic updated\ntext';
    if (field.controller!.text != initial) {
      throw StateError('Editor did not load the synthetic source');
    }
    if (mode != 'lock') {
      field.controller!.text = 'Synthetic close-save';
      await windowManager.close();
      await waitFor(() => find.byType(AlertDialog).evaluate().isNotEmpty);
      final button =
          find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: mode == 'save'
                        ? find.byType(FilledButton)
                        : find.widgetWithText(TextButton, t.fileEditorDiscard),
                  )
                  .evaluate()
                  .single
                  .widget
              as ButtonStyleButton;
      await report.invokeMethod('edited');
      button.onPressed!();
      return;
    }
    field.controller!.text = 'Synthetic updated\ntext';
    await waitFor(
      () =>
          (find.byKey(const Key('file-editor-save')).evaluate().single.widget
                  as FilledButton)
              .onPressed !=
          null,
    );
    (find.byKey(const Key('file-editor-save')).evaluate().single.widget
            as FilledButton)
        .onPressed!();
    await waitFor(() => find.text(t.fileEditorStored).evaluate().isNotEmpty);
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final boundary =
        find.byType(RepaintBoundary).evaluate().first.renderObject!
            as RenderRepaintBoundary;
    final image = await boundary
        .toImage(pixelRatio: 1)
        .timeout(const Duration(seconds: 10));
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/file-editor-native.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    field.controller!.text = 'Synthetic unsaved';
    await windowManager.close();
    await waitFor(() => find.byType(AlertDialog).evaluate().isNotEmpty);
    final cancel =
        find
                .ancestor(
                  of: find.text(t.cancel),
                  matching: find.byType(TextButton),
                )
                .evaluate()
                .single
                .widget
            as TextButton;
    cancel.onPressed!();
    await waitFor(() => find.byType(AlertDialog).evaluate().isEmpty);
    if (field.controller!.text != 'Synthetic unsaved') {
      throw StateError('Cancel did not preserve the synthetic draft');
    }
    await report.invokeMethod('edited');
    debugPrint('Synthetic editor saved; close cancellation verified');
  } catch (error, stack) {
    debugPrint('Synthetic editor failed: $error\n$stack');
    await report.invokeMethod('failed');
  }
}

void main([List<String> args = const []]) {
  if (args.firstOrNull == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(() async {
      await runFileEditorIfNeeded();
      debugPrint('Synthetic editor started');
      await exerciseEditorWindow();
    }());
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native attachments, password rotation, import/export and Windows messages',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-portability-native-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final picker = SyntheticPicker();
      final previousPicker = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previousPicker);
      final catalog = VaultCatalog(
        directory: Directory('${directory.path}/profile'),
      );
      final seed = await catalog.legacy.store.create('Synthetic old password');
      debugPrint('Synthetic fixture ready');
      seed.lock();
      final source = File('${directory.path}/synthetic.bin');
      await source.writeAsBytes(List.generate(4097, (i) => i % 256));
      final desktop = DesktopController(
        settings: ShortcutStore(file: File('${directory.path}/settings.json')),
      );
      addTearDown(desktop.releaseResources);
      const capture = Key('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: SkySecretApp(
            desktop: desktop,
            clipboard: FakeClipboard(),
            vaultCatalog: catalog,
          ),
        ),
      );
      await desktop.initialize();
      debugPrint('Synthetic desktop ready');
      await desktop.show();
      await windowManager.setSize(const Size(400, 520));
      await tester.pumpAndSettle();
      expect(
        await const MethodChannel('skysecret/system_lock')
            .invokeMethod<bool>('ready'),
        isTrue,
      );
      final hwnd = ownRunnerWindow();
      var editorResult = Completer<bool>();
      var editorScenario = 'lock';
      const editorReport = WindowMethodChannel(
        'skysecret/test-editor-report',
        mode: ChannelMode.unidirectional,
      );
      await editorReport.setMethodCallHandler((call) async {
        if (call.method == 'scenario') return editorScenario;
        if (!editorResult.isCompleted) {
          editorResult.complete(call.method == 'edited');
        }
        return true;
      });
      addTearDown(() => editorReport.setMethodCallHandler(null));
      using((arena) {
        final owner = arena<Uint32>();
        win32.GetWindowThreadProcessId(hwnd, owner);
        expect(owner.value, win32.GetCurrentProcessId());
      });
      Future<void> tap(String key) async {
        debugPrint('Test action: $key');
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        debugPrint('Test action completed: $key');
      }

      Future<void> shot(String name) async {
        await desktop.show();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await boundary
            .toImage(pixelRatio: 1)
            .timeout(const Duration(seconds: 10));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/qa').create(recursive: true);
        await File('build/qa/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await tester.enterText(
        find.byKey(const Key('vault-master')),
        'Synthetic old password',
      );
      await tap('open-vault');
      await tap('add-entry');
      await tester.enterText(
        find.byKey(const Key('entry-title')),
        'Synthetic file record',
      );
      picker.openPath = source.path;
      await tap('save-entry');
      await tap('add-file');
      await shot('files-debug');
      expect(find.text(t.vaultWriteFailed), findsNothing);
      expect(find.text(t.vaultFormatFailed), findsNothing);
      expect(find.text(t.vaultInvalidFilename), findsNothing);
      expect(find.text('synthetic.bin'), findsOneWidget);
      for (final locale in AppLocale.values) {
        await LocaleSettings.setLocale(locale);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('synthetic.bin'));
        await tester.pumpAndSettle();
        await shot('files-${locale.name}-400');
      }
      await tap('vault-settings');
      for (final locale in AppLocale.values) {
        await LocaleSettings.setLocale(locale);
        await tester.pumpAndSettle();
        await shot('settings-normal-${locale.name}-400');
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        for (final key in [
          'auto-lock-switch',
          'export-vault',
          'change-master',
        ]) {
          await mouse.moveTo(tester.getCenter(find.byKey(Key(key))));
          await tester.pumpAndSettle();
          await shot('settings-$key-hover-${locale.name}-400');
        }
        await mouse.removePointer();
      }
      await tap('change-master');
      for (final locale in AppLocale.values) {
        await LocaleSettings.setLocale(locale);
        await tester.pumpAndSettle();
        await shot('change-password-${locale.name}-400');
      }
      await tester.enterText(
        find.byKey(const Key('current-master')),
        'Synthetic old password',
      );
      await tester.enterText(
        find.byKey(const Key('transfer-master')),
        'Synthetic new password',
      );
      await tester.enterText(
        find.byKey(const Key('transfer-confirm')),
        'Synthetic new password',
      );
      await tap('confirm-password-action');
      final verified = await catalog.legacy.store.unlock(
        'Synthetic new password',
      );
      expect(
        verified.entries.singleWhere((e) => e.isFile).attachments.single.bytes,
        await source.readAsBytes(),
      );
      verified.lock();
      picker.savePath = '${directory.path}/backup.smv';
      await tap('vault-settings');
      await tap('export-vault');
      expect(await File(picker.savePath!).exists(), isTrue);
      await tap('lock-vault');
      picker.openPath = picker.savePath;
      await tap('vault-switcher');
      await tester.tap(find.text(t.vaultImport));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transfer-master')),
        'Synthetic new password',
      );
      await tap('confirm-password-action');
      expect((await catalog.list()).length, 2);
      final imported = (await catalog.list()).last;
      final restored = await imported.store.unlock('Synthetic new password');
      expect(
        restored.entries.singleWhere((e) => e.isFile).attachments.single.bytes,
        await source.readAsBytes(),
      );
      restored.lock();
      picker.savePath = '${directory.path}/extracted.bin';
      await tester.ensureVisible(find.byTooltip(t.vaultSaveAttachment));
      await tester.tap(find.byTooltip(t.vaultSaveAttachment));
      await tester.pumpAndSettle();
      expect(
        await File(picker.savePath!).readAsBytes(),
        await source.readAsBytes(),
      );
      picker.savePath = '${directory.path}/unsupported-original.bin';
      await tester.tap(find.text('synthetic.bin'));
      await tester.pumpAndSettle();
      expect(
        await File(picker.savePath!).readAsBytes(),
        await source.readAsBytes(),
      );
      await tap('vault-settings');
      await tap('auto-lock-switch');
      await tap('save-vault-preferences');
      final textSource = File('${directory.path}/synthetic.txt');
      await textSource.writeAsBytes(utf8.encode('Synthetic original\r\ntext'));
      picker.openPath = textSource.path;
      await tap('add-file');
      await tester.ensureVisible(find.text('synthetic.txt'));
      await tester.tap(find.text('synthetic.txt'));
      await tester.pumpAndSettle();
      expect(
        await editorResult.future.timeout(const Duration(seconds: 45)),
        isTrue,
      );
      final edited = await imported.store.unlock('Synthetic new password');
      expect(
        utf8.decode(
          edited.entries
              .singleWhere((e) => e.title == 'synthetic.txt')
              .attachments
              .single
              .bytes,
        ),
        'Synthetic updated\r\ntext',
      );
      edited.lock();
      debugPrint('Synthetic edited bytes verified');
      expect((await WindowController.getAll()).length, greaterThanOrEqualTo(2));
      for (final event in [(0x02B1, 7), (0x0218, 4), (0x0218, 18)]) {
        win32.PostMessage(
          hwnd,
          event.$1,
          win32.WPARAM(event.$2),
          const win32.LPARAM(0),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vault-master')), findsOneWidget);
        if (event.$1 == 0x02B1) {
          for (
            var i = 0;
            i < 30 && (await WindowController.getAll()).length > 1;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect((await WindowController.getAll()).length, 1);
        }
        expect(find.text('Synthetic file record'), findsNothing);
        await tester.enterText(
          find.byKey(const Key('vault-master')),
          'Synthetic new password',
        );
        await tap('open-vault');
      }
      for (final scenario in ['discard', 'save']) {
        editorScenario = scenario;
        editorResult = Completer<bool>();
        await tester.ensureVisible(find.text('synthetic.txt'));
        await tester.tap(find.text('synthetic.txt'));
        await tester.pumpAndSettle();
        expect(
          await editorResult.future.timeout(const Duration(seconds: 45)),
          isTrue,
        );
        for (
          var i = 0;
          i < 100 && (await WindowController.getAll()).length > 1;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect((await WindowController.getAll()).length, 1);
        final saved = await imported.store.unlock('Synthetic new password');
        expect(
          utf8.decode(
            saved.entries
                .singleWhere((e) => e.title == 'synthetic.txt')
                .attachments
                .single
                .bytes,
          ),
          scenario == 'save'
              ? 'Synthetic close-save'
              : 'Synthetic updated\r\ntext',
        );
        saved.lock();
        debugPrint('Synthetic close-$scenario verified');
      }
      await tap('vault-settings');
      await tap('change-master');
      await tester.enterText(
        find.byKey(const Key('transfer-master')),
        'Synthetic draft',
      );
      win32.PostMessage(
        hwnd,
        0x02B1,
        const win32.WPARAM(7),
        const win32.LPARAM(0),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('vault-master')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
