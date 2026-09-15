import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/os/windows/desktop_controller.dart';
import 'core/desktop/clipboard/sensitive_clipboard_boundary.dart';
import 'core/os/windows/windows_instance.dart';
import 'core/sync/github/github_backup.dart';
import 'i18n/translations.g.dart';
import 'ui/editor/file_editor_window.dart';
import 'ui/authenticator/totp_window.dart';
import 'ui/search/vault_search_window.dart';

Future<void> main(List<String> args) async {
  final clipboardBoundary = SensitiveClipboardBoundary();
  SensitiveWidgetsBinding(clipboardBoundary);
  await LocaleSettings.useDeviceLocale();
  if (!Platform.isWindows) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(t.windowsOnly))),
      ),
    );
    return;
  }
  if (await runFileEditorIfNeeded(clipboardBoundary: clipboardBoundary)) return;
  if (await runTotpWindowIfNeeded()) return;
  if (await runSearchWindowIfNeeded(clipboardBoundary: clipboardBoundary)) return;
  final WindowsInstance instance;
  try {
    instance = WindowsInstance();
  } catch (_) {
    exit(1);
  }
  if (!instance.isPrimary) {
    instance.dispose();
    exit(0);
  }
  final desktop = DesktopController(onExit: instance.dispose);
  instance.listen(() => unawaited(desktop.show()));
  final backup = GitHubBackup.local();
  runApp(SkySecretApp(desktop: desktop, githubBackup: backup, clipboardBoundary: clipboardBoundary));
  unawaited(backup.initialize());
  try {
    await desktop.initialize();
  } catch (_) {
    instance.dispose();
    exit(1);
  }
}
