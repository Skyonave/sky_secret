import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../desktop/browser.dart';
import '../../github/github_api.dart';
import '../../github/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../shared/sensitive_text_editing.dart';

String githubStatusLabel(GitHubBackup backup) => switch (backup.status) {
  BackupStatus.disconnected => t.githubDisconnected,
  BackupStatus.ready => t.githubReady,
  BackupStatus.pending => t.githubPending,
  BackupStatus.working => t.githubWorking,
  BackupStatus.synced => t.githubSynced,
  BackupStatus.conflict => t.githubConflict,
  BackupStatus.failed => t.githubFailed,
};

String githubProblemLabel(GitHubProblem problem) => switch (problem) {
  GitHubProblem.network => t.githubNetworkError,
  GitHubProblem.authorization => t.githubAuthError,
  GitHubProblem.denied => t.githubAccessError,
  GitHubProblem.missing => t.githubMissingError,
  GitHubProblem.conflict => t.githubConflictHelp,
  GitHubProblem.repositoryChanged => t.githubRepositoryChangedError,
  GitHubProblem.repositorySetup => t.githubRepositorySetupError,
  GitHubProblem.format => t.githubFormatError,
  GitHubProblem.storage => t.githubStorageError,
  GitHubProblem.identity => t.githubIdentityError,
  GitHubProblem.configuration => t.githubConfigurationError,
  GitHubProblem.cancelled => t.cancel,
};

class GitHubDialog extends StatefulWidget {
  final bool restoreSeparately;
  final GitHubBackup backup;
  final Future<bool> Function(RemoteVault)? linkExisting;
  final Future<bool> Function(Uint8List, RemoteVault?) restore;

  const GitHubDialog({
    super.key,
    required this.backup,
    required this.restore,
    this.linkExisting,
    this.restoreSeparately = false,
  });

  @override
  State<GitHubDialog> createState() => _GitHubDialogState();
}

class _GitHubDialogState extends State<GitHubDialog> {
  static const _controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  static const _buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 44)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    shape: WidgetStatePropertyAll(_controlShape),
    visualDensity: VisualDensity.standard,
  );
  final _token = TextEditingController();
  late final _repository = TextEditingController(
    text: widget.backup.repositoryAddress,
  );
  bool _initializeRepository = false;
  bool _restrictedToken = false;
  bool _editConnection = false;
  bool _restoring = false;
  late bool _linkForSync = widget.restoreSeparately == false;
  String? _error;

  Widget _tileSurface(Widget child) => Material(
    type: MaterialType.transparency,
    shape: _controlShape,
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  InputDecoration _fieldDecoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );

  @override
  void dispose() {
    widget.backup.cancelConnection();
    _token.clear();
    _token.dispose();
    _repository.dispose();
    super.dispose();
  }

  Future<void> _openBrowser(String url) async {
    try {
      if (!openBrowser(url) && mounted) {
        setState(() => _error = t.githubBrowserError);
      }
    } catch (_) {
      if (mounted) setState(() => _error = t.githubBrowserError);
    }
  }

  Future<void> _connect() async {
    final token = _token.text;
    _token.clear();
    await widget.backup.connectToken(
      token,
      _repository.text,
      initializeRepository: _initializeRepository,
    );
    if (mounted && widget.backup.problem == null) {
      setState(() => _editConnection = false);
    }
  }

  Future<void> _restore(RemoteVault vault) async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final bytes = await widget.backup.download(vault);
      if (bytes == null || !mounted) return;
      final synchronized = widget.restoreSeparately == false && _linkForSync;
      if (await widget.restore(bytes, synchronized ? vault : null) && mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = t.githubRestoreError);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _recoverConnection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.githubRecoverConnection),
        content: Text(t.githubRecoverConnectionHelp),
        actions: [
          TextButton(
            style: _buttonStyle,
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: _buttonStyle,
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.githubRecoverConnection),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.backup.resetDamagedConnection();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.backup,
    builder: (context, _) {
      final backup = widget.backup;
      final disabled = backup.busy || _restoring || !backup.usable;
      return AlertDialog(
        title: Text(t.githubTitle),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  githubStatusLabel(backup),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                if (backup.problem != null) ...[
                  Text(
                    githubProblemLabel(backup.problem!),
                    style: const TextStyle(color: Color(0xFFFFCB8A)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (backup.connectionNeedsRecovery) ...[
                  OutlinedButton(
                    style: _buttonStyle,
                    onPressed: backup.busy ? null : _recoverConnection,
                    child: Text(t.githubRecoverConnection),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFFCB8A)),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!backup.signedIn || _editConnection || backup.problem == GitHubProblem.authorization) ...[
                  Text(
                    t.githubSetupHelp,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.githubSetupRepositoryStep,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.githubSetupRepositoryHelp,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: _buttonStyle,
                    onPressed: disabled ? null : () => _openBrowser('https://github.com/new'),
                    child: Text(
                      t.githubCreateRepository,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.githubSetupTokenStep,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.githubSetupTokenHelp,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: _buttonStyle,
                    onPressed: disabled
                        ? null
                        : () => _openBrowser(
                            'https://github.com/settings/personal-access-tokens/new?name=SkySecret&expires_in=90&contents=write',
                          ),
                    child: Text(
                      t.githubCreateToken,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.githubSetupConnectStep,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.githubSetupConnectHelp,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SensitiveTextEditing(
                    controller: _repository,
                    enabled: !disabled,
                    readOnly: false,
                    obscureText: false,
                    builder: (context, menuBuilder) => TextField(
                      contextMenuBuilder: menuBuilder,
                      enableIMEPersonalizedLearning: false,

                      controller: _repository,
                      enabled: !disabled,
                      decoration: _fieldDecoration(
                        t.githubRepositoryAddress,
                        hint: 'https://github.com/owner/repo',
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SensitiveTextEditing(
                    controller: _token,
                    enabled: !disabled,
                    readOnly: false,
                    obscureText: true,
                    builder: (context, menuBuilder) => TextField(
                      contextMenuBuilder: menuBuilder,
                      enableIMEPersonalizedLearning: false,

                      controller: _token,
                      enabled: !disabled,
                      obscureText: true,
                      decoration: _fieldDecoration(t.githubToken),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      t.githubTokenHelp,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _tileSurface(
                    CheckboxListTile(
                      value: _restrictedToken,
                      onChanged: disabled || widget.restoreSeparately
                          ? null
                          : (value) => setState(
                              () => _restrictedToken = value ?? false,
                            ),
                      contentPadding: const EdgeInsets.all(12),
                      visualDensity: VisualDensity.standard,
                      shape: _controlShape,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        t.githubTokenConfirmation,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _tileSurface(
                    CheckboxListTile(
                      value: _initializeRepository,
                      onChanged: disabled
                          ? null
                          : (value) => setState(
                              () => _initializeRepository = value ?? false,
                            ),
                      contentPadding: const EdgeInsets.all(12),
                      visualDensity: VisualDensity.standard,
                      shape: _controlShape,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        t.githubInitializeRepository,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: _buttonStyle,
                    onPressed: disabled || !_restrictedToken ? null : _connect,
                    child: Text(t.githubConnect, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 20),
                ],
                if (backup.signedIn) ...[
                  if (backup.login != null)
                    Text(
                      backup.login!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (backup.repository != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        backup.repository!.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: _buttonStyle,
                    onPressed: disabled ? null : backup.discover,
                    child: Text(
                      t.githubFindBackups,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.githubAutoBackupHelp,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    style: _buttonStyle,
                    onPressed: disabled ? null : backup.sync,
                    child: Text(t.githubBackupNow, textAlign: TextAlign.center),
                  ),
                  if (backup.lastSync != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        t.githubLastBackup(
                          time: MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(
                              backup.lastSync!.toLocal(),
                            ),
                            alwaysUse24HourFormat: true,
                          ),
                          date: MaterialLocalizations.of(context).formatShortDate(backup.lastSync!.toLocal()),
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  if (backup.conflicts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      t.githubConflictHelp,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: _buttonStyle,
                      onPressed: disabled ? null : backup.keepBoth,
                      child: Text(
                        t.githubKeepBoth,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    t.githubRestore,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.githubRestoreHelp,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _tileSurface(
                    CheckboxListTile(
                      value: _linkForSync,
                      onChanged: disabled ? null : (value) => setState(() => _linkForSync = value ?? true),
                      contentPadding: const EdgeInsets.all(12),
                      shape: _controlShape,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        t.syncLink,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (backup.remoteVaults.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t.githubNoBackups),
                    ),
                  for (final vault in backup.remoteVaults)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      title: Text(
                        t.vaultIdentifier(id: vault.id.substring(0, 8)),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text('${(vault.size / 1024).ceil()} KiB'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.linkExisting != null)
                            IconButton(
                              tooltip: t.syncRelink,
                              onPressed: disabled
                                  ? null
                                  : () async {
                                      setState(() => _restoring = true);
                                      try {
                                        if (await widget.linkExisting!(vault) && context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _restoring = false);
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.link_rounded),
                            ),
                          IconButton(
                            tooltip: t.githubRestore,
                            onPressed: disabled ? null : () => _restore(vault),
                            icon: const Icon(Icons.download_rounded),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    t.githubHistoryHelp,
                    style: const TextStyle(fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: _buttonStyle,
                    onPressed: disabled
                        ? null
                        : () => setState(
                            () => _editConnection = !_editConnection,
                          ),
                    child: Text(
                      t.githubReplaceToken,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: _buttonStyle,
                    onPressed: disabled ? null : backup.disconnect,
                    child: Text(
                      t.githubDisconnect,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: _buttonStyle,
                    onPressed: disabled
                        ? null
                        : () => _openBrowser(
                            'https://github.com/settings/personal-access-tokens',
                          ),
                    child: Text(
                      t.githubManageTokens,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (backup.busy || _restoring)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: _buttonStyle,
            onPressed: () => Navigator.pop(context),
            child: Text(t.githubClose, textAlign: TextAlign.center),
          ),
        ],
      );
    },
  );
}
