import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'crypto/crypto.dart';
import 'desktop/desktop_actions.dart';
import 'desktop/sensitive_clipboard.dart';
import 'desktop/sensitive_clipboard_boundary.dart';
import 'desktop/vault_preferences.dart';
import 'github/github_backup.dart';
import 'i18n/translations.g.dart';
import 'ui/manager/manager_window.dart';
import 'ui/shared/app_theme.dart';

export 'ui/manager/manager_window.dart' show ManagerWindow;

class SkySecretApp extends StatelessWidget {
  final DesktopActions desktop;
  final SensitiveClipboard? clipboard;
  final SensitiveClipboardBoundary? clipboardBoundary;
  final VaultStore? vaultStore;
  final VaultCatalog? vaultCatalog;
  final VaultPreferences? vaultPreferences;
  final GitHubBackup? githubBackup;

  const SkySecretApp({
    super.key,
    required this.desktop,
    this.clipboard,
    this.clipboardBoundary,
    this.vaultStore,
    this.vaultCatalog,
    this.vaultPreferences,
    this.githubBackup,
  });

  @override
  Widget build(BuildContext context) => TranslationProvider(child: Builder(builder: _buildApp));

  Widget _buildApp(BuildContext context) => MaterialApp(
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    title: t.appName,
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: ManagerWindow(
      desktop: desktop,
      clipboard: clipboard,
      clipboardBoundary: clipboardBoundary,
      vaultStore: vaultStore,
      vaultCatalog: vaultCatalog,
      vaultPreferences: vaultPreferences,
      githubBackup: githubBackup,
    ),
  );
}
