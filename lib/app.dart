import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/crypto/crypto.dart';
import 'core/desktop/desktop_actions.dart';
import 'core/desktop/clipboard/sensitive_clipboard.dart';
import 'core/desktop/clipboard/sensitive_clipboard_boundary.dart';
import 'core/settings/vault_preferences.dart';
import 'core/sync/github/github_backup.dart';
import 'i18n/translations.g.dart';
import 'ui/manager/manager_window.dart';
import 'ui/shared/app_theme.dart';
import 'ui/shared/desktop_menu.dart';

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
    navigatorObservers: [DesktopMenuObserver()],
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
