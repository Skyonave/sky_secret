import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'desktop/desktop_controller.dart';
import 'desktop/sensitive_clipboard_boundary.dart';
import 'desktop/windows_instance.dart';
import 'github/github_backup.dart';
import 'i18n/translations.g.dart';
import 'ui/editor/file_editor_window.dart';

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
