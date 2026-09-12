import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../crypto/crypto.dart';
import '../../desktop/file_viewer_manager.dart';
import '../../desktop/ssh_connections.dart';
import '../../desktop/vault_preferences.dart';
import '../../desktop/window_privacy.dart';
import '../../files/text_document.dart';
import '../../files/vault_file_import.dart';
import '../../files/vault_text_file.dart';
import '../../github/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../github/github_dialog.dart';
import '../shared/inset_menu_item.dart';
import '../shared/sensitive_text_editing.dart';
import 'password_options_dialog.dart';
import 'vault_name_dialog.dart';
import 'vault_password_dialog.dart';

part '_vault_tree.dart';
part '_vault_field.dart';
part '_vault_entry_draft.dart';
part '_vault_entry_editor.dart';
part '_vault_header.dart';
part '_vault_unlock_form.dart';
part '_vault_preferences_dialog.dart';
part '_vault_entry_card.dart';
part '_vault_text_file_dialog.dart';

class VaultPanel extends StatefulWidget {
  final VaultStore? store;
  final VaultCatalog? catalog;
  final VaultPreferences? preferences;
  final GitHubBackup? githubBackup;
  final ValueChanged<bool>? onSshAuthorizationChanged;
  final Future<bool> Function(String) copySecret;
  final Future<void> Function() clearClipboard;

  const VaultPanel({
    super.key,
    this.store,
    this.catalog,
    this.preferences,
    this.githubBackup,
    this.onSshAuthorizationChanged,
    required this.copySecret,
    required this.clearClipboard,
  });

  @override
  State<VaultPanel> createState() => VaultPanelState();
}

class VaultPanelState extends State<VaultPanel> {
  VaultStore? _store;
  VaultCatalog? _catalog;
  List<VaultReference> _vaults = [];
  String? _selectedVaultId;
  final _knownVaultNames = <String, String>{};
  VaultSession? _session;
  bool _exists = false;
  bool _loading = true;
  bool _busy = false;
  bool _waitingForPassword = false;
  bool _editing = false;
  String? _editingId;
  String? _error;
  final _collapsedFolders = <String>{};
  int _generationLength = 24;
  bool _generationSymbols = true;
  String? _entryFolderId;
  final _vaultName = TextEditingController();
  final _renameName = TextEditingController();
  bool _renamingVault = false;
  bool _renameInvalid = false;
  final _treeKey = GlobalKey<_VaultTreeState>();
  final _generator = PasswordGenerator();
  final _draft = _VaultEntryDraft();
  Timer? _idleTimer;
  Timer? _copyNoticeTimer;
  ({VaultSession session, String entryId})? _copyNotice;
  VaultPreferences? _preferences;
  bool _autoLockEnabled = true;
  bool _lockWhenHidden = true;
  bool _savingPreferences = false;
  final _master = TextEditingController();
  final _confirmation = TextEditingController();
  bool _editingSsh = false;
  late final SshConnections _sshConnections;
  final _viewers = FileViewerManager();
  int _securityEpoch = 0;
  static const _systemLock = MethodChannel('skysecret/system_lock');
  bool _sensitiveDialogOpen = false;

  Future<bool> _confirmSshHost(String prompt) async {
    if (!mounted || _session == null || _session!.isLocked || _sensitiveDialogOpen) {
      return false;
    }
    _sensitiveDialogOpen = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t.sshHostKeyTitle),
              scrollable: true,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.sshHostKeyHelp),
                  const SizedBox(height: 16),
                  SelectableText(prompt),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(t.sshTrustHost),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _sensitiveDialogOpen = false;
    }
  }

  Future<void> _connectSsh(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return;
    try {
      await _sshConnections.start(_selectedVaultId ?? 'local', session, entry);
      if (mounted && _session == session && !session.isLocked) {
        _notice(t.sshStarted);
      }
    } on PlatformException catch (error) {
      if (!mounted || _session != session || session.isLocked) return;
      _notice(switch (error.code) {
        'missing' => t.sshMissing,
        'active' => t.sshActive,
        'limit' => t.sshLimit,
        'invalid' => t.sshInvalid,
        _ => t.sshFailed,
      });
    } catch (_) {
      if (mounted && _session == session && !session.isLocked) {
        _notice(t.sshFailed);
      }
    }
  }

  Future<void> synchronize(GitHubBackup backup) async {
    if (_busy || _loading || backup.busy) return;
    if (_editing || _renamingVault || _viewers.hasOpenViewers) {
      _notice(t.syncFinishEditing);
      return;
    }
    if (!backup.signedIn) {
      await showGitHub(backup);
      return;
    }
    final session = _session;
    if (session == null || session.isLocked || _selectedVaultId == null) {
      _notice(t.syncUnlock);
      await showGitHub(backup);
      return;
    }
    final epoch = _securityEpoch;
    _touchActivity();
    var openRemoteCopy = false;
    await _operation(() async {
      await backup.synchronizeVault(
        _selectedVaultId!,
        _store!,
        session,
      );
      if (!mounted || epoch != _securityEpoch || session.isLocked) return;
      if (session.name != null) {
        _knownVaultNames[_selectedVaultId!] = session.name!;
      }
      setState(() {});
      final message = _synchronizationMessage(backup);
      openRemoteCopy =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(backup.syncKeyChanged ? t.syncKeyChangedTitle : t.syncNow),
              content: Text(message),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(backup.syncKeyChanged ? t.syncKeepLocal : t.githubClose),
                ),
                if (backup.syncKeyChanged)
                  TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t.syncOpenRemoteCopy),
                  ),
              ],
            ),
          ) ??
          false;
    });
    if (openRemoteCopy && mounted && epoch == _securityEpoch) {
      await showGitHub(backup, restoreSeparately: true);
    }
  }

  String _synchronizationMessage(GitHubBackup backup) {
    if (backup.syncKeyChanged) return t.syncKeyChanged;
    if (backup.syncRollback) return t.syncRollback;
    if (backup.problem case final problem?) return githubProblemLabel(problem);
    if (_store!.snapshotCleanupPending) return t.vaultSnapshotCleanupWarning;
    if (backup.mergedConflicts > 0) return t.syncConflicts(count: backup.mergedConflicts);
    return t.syncDone;
  }

  Future<void> showGitHub(GitHubBackup backup, {bool restoreSeparately = false}) async {
    if (_busy || _loading || _editing || _catalog == null) return;
    await _showGitHubDialog(backup, restoreSeparately: restoreSeparately);
  }

  Future<void> _showGitHubDialog(GitHubBackup backup, {required bool restoreSeparately}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => GitHubDialog(
        backup: backup,
        restoreSeparately: restoreSeparately,
        linkExisting: restoreSeparately || _session == null
            ? null
            : (remote) async {
                final session = _session;
                final store = _store;
                final id = _selectedVaultId;
                final epoch = _securityEpoch;
                if (session == null || store == null || id == null || session.isLocked) {
                  return false;
                }
                if (!await _confirm(t.syncRelink, t.syncRelinkHelp) || !mounted || epoch != _securityEpoch) {
                  return false;
                }
                await backup.linkExistingVault(
                  id,
                  store,
                  session,
                  remote,
                );
                if (!mounted || epoch != _securityEpoch) return false;
                if (backup.problem != null) {
                  _notice(backup.syncKeyChanged ? t.syncKeyChanged : githubProblemLabel(backup.problem!));
                  return false;
                }
                _notice(t.syncRelinkDone);
                return true;
              },
        restore: (bytes, remote) async {
          if (remote != null) {
            final existing = backup.localForRemote(remote.id);
            if (existing != null && (await _catalog!.list()).any((v) => v.id == existing)) {
              await _selectVault(existing);
              if (mounted) _notice(t.syncAlreadyLinked);
              return true;
            }
          }
          final epoch = _securityEpoch;
          final passwords = await _passwordPrompt();
          if (passwords == null || !mounted || epoch != _securityEpoch) {
            return false;
          }
          var restored = false;
          await _operation(() async {
            final target = _catalog!.newVault();
            if (remote != null) {
              await backup.bindSynchronizedImport(target.id, remote);
            }
            late VaultSession session;
            try {
              session = await target.store.importEncryptedSnapshot(
                bytes,
                passwords.password,
                allowed: () => mounted && epoch == _securityEpoch,
              );
            } catch (_) {
              if (remote != null && !await target.store.exists()) {
                await backup.cancelSynchronizedImport(target.id);
              }
              rethrow;
            }
            if (!mounted || epoch != _securityEpoch) {
              session.lock();
              return;
            }
            _session?.lock();
            _viewers.closeAll();
            unawaited(widget.clearClipboard());
            setState(() {
              _session = session;
              _store = target.store;
              _selectedVaultId = target.id;
              _vaults.add(target);
              _exists = true;
              _master.clear();
              _confirmation.clear();
              _vaultName.clear();
              _clearEditor();
              if (session.name != null) {
                _knownVaultNames[target.id] = session.name!;
              }
            });
            _touchActivity();
            restored = true;
          });
          if (!restored && mounted && epoch == _securityEpoch) {
            _notice(t.githubRestoreError);
          }
          return restored;
        },
      ),
    );
  }

  Object? get fileDropSession => _session;

  String? get fileDropFolderId => _treeKey.currentState?.nativeFolderId;

  void updateFileDropPosition(Offset? position) {
    _treeKey.currentState?.nativeHover(canAcceptFileDrop ? position : null);
  }

  bool get canAcceptFileDrop =>
      !_loading &&
      _session != null &&
      !_session!.isLocked &&
      !_busy &&
      !_editing &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  String get fileDropHint => _session == null || _session!.isLocked
      ? t.vaultDropLocked
      : (_busy || _editing || !(ModalRoute.of(context)?.isCurrent ?? true))
      ? t.vaultDropBusy
      : t.vaultDropHint;

  Future<void> importDroppedFiles(
    List<String> paths, {
    required Object? sessionToken,
    String? folderId,
  }) async {
    if (_session != sessionToken || !canAcceptFileDrop) {
      _notice(fileDropHint);
      return;
    }
    final session = _session!;
    if (folderId != null && session.folders.every((folder) => folder.id != folderId)) return;
    await _operation(() => _importFiles(session, paths, folderId: folderId));
  }

  Future<void> _importFiles(
    VaultSession session,
    List<String> paths, {
    String? folderId,
  }) async {
    try {
      final entries = await readVaultFiles(session, paths, folderId: folderId);
      if (entries.isEmpty || !mounted || session.isLocked || _session != session) {
        return;
      }
      final organization = VaultOrganization(entries: session.entries, folders: session.folders);
      organization.appendEntries(entries, folderId);
      await _store!.save(session, organization.entries, folders: organization.folders);
      if (mounted && !session.isLocked && _session == session) {
        setState(() => _collapsedFolders.remove(folderId ?? ''));
        _notice(t.vaultFilesAdded(count: entries.length));
      }
    } on FileImportException catch (error) {
      if (!mounted || session.isLocked || _session != session) return;
      _notice(switch (error.problem) {
        FileImportProblem.limit => t.vaultAttachmentLimit,
        FileImportProblem.name => t.vaultInvalidFilename,
        FileImportProblem.notFile => t.vaultDropFilesOnly,
        FileImportProblem.changed => t.vaultDropChanged,
      });
    }
  }

  void onWindowHidden() {
    if (!mounted || !_lockWhenHidden) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _lock();
  }

  @override
  void initState() {
    super.initState();
    _sshConnections = SshConnections(
      confirmHost: _confirmSshHost,
      onAuthorizationChanged: (pending) => widget.onSshAuthorizationChanged?.call(pending),
      onExit: (success) {
        if (mounted) _notice(success ? t.sshClosed : t.sshFailed);
      },
    );
    HardwareKeyboard.instance.addHandler(_onKeyActivity);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerActivity);
    _systemLock.setMethodCallHandler((call) async {
      if (call.method == 'lock' && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _lock();
      }
    });
    unawaited(_checkSystemLock());
    unawaited(_load());
  }

  Future<void> _checkSystemLock() async {
    try {
      final ready = await _systemLock.invokeMethod<bool>('ready');
      if (mounted && ready == false) _notice(t.vaultSystemLockFailed);
    } on MissingPluginException catch (_) {
    } catch (_) {
      if (mounted) _notice(t.vaultSystemLockFailed);
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<VaultPasswords?> _passwordPrompt({
    bool change = false,
  }) async {
    _sensitiveDialogOpen = true;
    setState(() => _waitingForPassword = true);
    try {
      return await showDialog<VaultPasswords>(
        context: context,
        builder: (_) => VaultPasswordDialog(change: change),
      );
    } finally {
      _sensitiveDialogOpen = false;
      if (mounted) setState(() => _waitingForPassword = false);
    }
  }

  Future<void> _operation(Future<void> Function() action) async {
    if (_busy) return;
    final epoch = _securityEpoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on MasterPasswordPolicyException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'password-policy');
      }
    } on MemoryProtectionException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'memory-protection');
      }
    } on VaultUnlockException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'unlock');
    } on VaultFormatException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'format');
    } on VaultConflictException {
      if (mounted && epoch == _securityEpoch) _notice(t.vaultDestinationExists);
    } catch (_) {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'io');
    } finally {
      if (mounted && epoch == _securityEpoch) setState(() => _busy = false);
    }
  }

  Future<void> _importVault({File? snapshot}) async {
    if (_catalog == null || _busy) return;
    final epoch = _securityEpoch;
    await _operation(() async {
      final source = snapshot != null
          ? XFile(snapshot.path)
          : await openFile(
              acceptedTypeGroups: [
                XTypeGroup(label: t.vaultAllFiles),
                XTypeGroup(label: t.appName, extensions: const ['smv']),
              ],
            );
      if (!mounted || source == null || epoch != _securityEpoch) return;
      final passwords = await _passwordPrompt();
      if (!mounted || passwords == null || epoch != _securityEpoch) return;
      final target = _catalog!.newVault();
      final session = await target.store.importFrom(
        File(source.path),
        passwords.password,
        allowed: () => mounted && epoch == _securityEpoch,
      );
      if (!mounted || epoch != _securityEpoch) {
        session.lock();
        return;
      }
      _session?.lock();
      _viewers.closeAll();
      unawaited(widget.clearClipboard());
      setState(() {
        _session = session;
        _store = target.store;
        _selectedVaultId = target.id;
        _vaults.add(target);
        _exists = true;
        _master.clear();
        _confirmation.clear();
        _vaultName.clear();
        _clearEditor();
        if (session.name != null) _knownVaultNames[target.id] = session.name!;
      });
      _touchActivity();
      _notice(t.vaultImportDone);
    });
  }

  Future<void> _exportVault() async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      final destination = await getSaveLocation(
        suggestedName: 'vault-backup-${DateTime.now().millisecondsSinceEpoch}.smv',
        acceptedTypeGroups: [
          XTypeGroup(label: t.appName, extensions: const ['smv']),
        ],
      );
      if (!mounted || destination == null || session.isLocked || _session != session) {
        return;
      }
      final path = destination.path.toLowerCase().endsWith('.smv') ? destination.path : '${destination.path}.smv';
      await _store!.exportTo(session, File(path));
      if (mounted && !session.isLocked) _notice(t.vaultExportDone);
    });
  }

  Future<void> _changePassword() async {
    final session = _session;
    if (session == null || _busy) return;
    await _operation(() async {
      final passwords = await _passwordPrompt(change: true);
      if (!mounted || passwords == null || session.isLocked || _session != session) {
        return;
      }
      final epoch = _securityEpoch;
      final replacement = await _store!.changePassword(
        session,
        passwords.current,
        passwords.password,
      );
      if (!mounted || epoch != _securityEpoch) {
        replacement.lock();
        return;
      }
      setState(() => _session = replacement);
      _viewers.closeAll();
      unawaited(widget.clearClipboard());
      _touchActivity();
      _notice(_store!.snapshotCleanupPending ? t.vaultSnapshotCleanupWarning : t.vaultPasswordChanged);
    });
  }

  Future<void> _createTextFile([String? folderId]) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || _sensitiveDialogOpen) return;
    VaultEntry? created;
    _sensitiveDialogOpen = true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _VaultTextFileDialog(
          create: (name) async {
            if (!mounted || _session != session || session.isLocked || _busy) return t.vaultWriteFailed;
            try {
              final organization = VaultOrganization(entries: session.entries, folders: session.folders);
              final entry = VaultTextFile.prepare(name: name, organization: organization, folderId: folderId);
              if (!await _persist(organization.entries, folders: organization.folders)) return t.vaultWriteFailed;
              if (!mounted || _session != session || session.isLocked) return t.vaultWriteFailed;
              created = session.entries.firstWhere((candidate) => candidate.id == entry.id);
              setState(() {
                _collapsedFolders.remove(folderId);
                final parent = session.folders.where((folder) => folder.id == folderId).firstOrNull?.parentId;
                _collapsedFolders.remove(parent);
              });
              return null;
            } on TextFileException catch (error) {
              return switch (error.problem) {
                TextFileProblem.invalidName => t.vaultTextNameInvalid,
                TextFileProblem.nameTaken => t.vaultTextNameTaken,
                TextFileProblem.limit => t.vaultLimit,
                TextFileProblem.location => t.vaultWriteFailed,
              };
            } on MemoryProtectionException {
              return t.vaultMemoryProtectionFailed;
            } catch (_) {
              return t.vaultWriteFailed;
            }
          },
        ),
      );
      if (mounted && accepted == true && _session == session && !session.isLocked && created != null) {
        await _openFile(created!);
      }
    } finally {
      _sensitiveDialogOpen = false;
    }
  }

  Future<void> _addFile([String? folderId]) async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      final selected = await openFile();
      if (!mounted || selected == null || session.isLocked || _session != session) {
        return;
      }
      await _importFiles(session, [selected.path], folderId: folderId);
    });
  }

  Future<void> _extractAttachment(VaultAttachment attachment) async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      final destination = await getSaveLocation(suggestedName: attachment.name);
      if (!mounted || destination == null || session.isLocked || _session != session) {
        return;
      }
      await VaultStore.extract(session, attachment, File(destination.path));
      if (mounted && !session.isLocked) _notice(t.vaultAttachmentSaved);
    });
  }

  Future<void> _openFile(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || !entry.isFile) return;
    var original = entry.attachments.single;
    final bytes = original.bytes;
    final TextDocument? document;
    try {
      document = TextDocument.decode(original.name, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final readable = document;
    if (readable == null) {
      _notice(t.fileEditorUnsupported);
      await _extractAttachment(original);
      return;
    }
    await _operation(
      () => _viewers.open(
        id: entry.id,
        name: original.name,
        text: readable.text,
        encoding: readable.encoding,
        locale: LocaleSettings.currentLocale.languageCode,
        isValid: () =>
            mounted && _session == session && !session.isLocked && session.entries.any((e) => e.id == entry.id),
        activity: _touchActivity,
        copy: widget.copySecret,
        clearClipboard: widget.clearClipboard,
        save: (text) async {
          if (!mounted || _session != session || session.isLocked || _busy) {
            return false;
          }
          final current = session.entries.where((e) => e.id == entry.id).firstOrNull;
          if (current == null || !current.isFile || !identical(current.attachments.single, original)) {
            return false;
          }
          try {
            final encoded = readable.encode(text);
            final VaultAttachment updated;
            try {
              updated = VaultAttachment(
                id: original.id,
                name: original.name,
                bytes: encoded,
              );
            } finally {
              encoded.fillRange(0, encoded.length, 0);
            }
            final replacement = VaultEntry.file(
              updated,
              id: current.id,
              folderId: current.folderId,
            ).withConflict(current.conflictOf).atPosition(current.folderId, current.order);
            if (!await _persist(
              session.entries.map((e) => e.id == entry.id ? replacement : e).toList(),
            )) {
              return false;
            }
            original = updated;
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }

  Future<void> _load() async {
    try {
      if (_store == null) {
        if (widget.store != null) {
          _store = widget.store;
        } else {
          _catalog = widget.catalog ?? VaultCatalog.local();
          _vaults = await _catalog!.list();
          if (_vaults.isEmpty) _vaults.add(_catalog!.legacy);
          _selectedVaultId = _vaults.first.id;
          _store = _vaults.first.store;
        }
      }
      if (_preferences == null) {
        _preferences =
            widget.preferences ??
            VaultPreferences(
              file: _catalog == null
                  ? null
                  : File(
                      '${_catalog!.directory.path}${Platform.pathSeparator}vault_preferences.json',
                    ),
            );
        try {
          _autoLockEnabled = await _preferences!.loadAutoLock();
          _lockWhenHidden = _preferences!.lockWhenHidden;
        } catch (_) {
          _autoLockEnabled = true;
          _lockWhenHidden = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.vaultPreferencesReadFailed)),
            );
          }
        }
      }
      final exists = await _store!.exists();
      if (mounted) {
        setState(() {
          _exists = exists;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'read';
          _selectedVaultId = null;
          _store = null;
        });
      }
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    if (_master.text.isEmpty) {
      setState(() => _error = 'required');
      return;
    }
    if (!_exists && _master.text != _confirmation.text) {
      setState(() => _error = 'mismatch');
      return;
    }
    if (!_exists && !MasterPasswordPolicy.accepts(_master.text)) {
      setState(() => _error = 'password-policy');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final epoch = _securityEpoch;
    final password = _master.text;
    _master.clear();
    _confirmation.clear();
    try {
      final session = _exists
          ? await _store!.unlock(password)
          : await _store!.create(
              password,
              name: _vaultName.text.trim().isEmpty ? null : _vaultName.text.trim(),
            );
      if (!mounted || epoch != _securityEpoch) {
        session.lock();
        return;
      }
      setState(() {
        _session = session;
        _exists = true;
        _vaultName.clear();
        if (_selectedVaultId != null && session.name != null) {
          _knownVaultNames[_selectedVaultId!] = session.name!;
        }
      });
      _touchActivity();
      if (_store!.snapshotCleanupPending) _notice(t.vaultSnapshotCleanupWarning);
    } on MasterPasswordPolicyException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'password-policy');
      }
    } on MemoryProtectionException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'memory-protection');
      }
    } on VaultUnlockException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'unlock');
    } on VaultFormatException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'format');
    } on VaultConflictException {
      if (!mounted || epoch != _securityEpoch) return;
      await _load();
      if (mounted) setState(() => _error = 'conflict');
    } catch (_) {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'io');
    } finally {
      if (mounted && epoch == _securityEpoch) setState(() => _busy = false);
    }
  }

  bool _onKeyActivity(KeyEvent event) {
    _touchActivity();
    return false;
  }

  void _onPointerActivity(PointerEvent event) => _touchActivity();

  void _touchActivity() {
    if (_session == null || !_autoLockEnabled) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 2), () {
      if (!mounted || _session == null) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _lock();
    });
  }

  Future<void> _showPreferences() async {
    final previousCapture = _preferences?.captureAllowed ?? false;
    final result = await showDialog<({bool idle, bool hidden, bool capture})>(
      context: context,
      builder: (context) => _VaultPreferencesDialog(
        autoLockEnabled: _autoLockEnabled,
        lockWhenHidden: _lockWhenHidden,
        captureAllowed: previousCapture,
        canManageVault: _session != null,
        busy: _busy,
        onExport: () => unawaited(_exportVault()),
        onChangePassword: () => unawaited(_changePassword()),
      ),
    );
    if (!mounted ||
        result == null ||
        (result.idle == _autoLockEnabled && result.hidden == _lockWhenHidden && result.capture == previousCapture)) {
      return;
    }
    setState(() => _savingPreferences = true);
    try {
      if (result.capture != previousCapture && !WindowPrivacy.setCaptureAllowed(result.capture)) {
        _notice(t.captureSettingFailed);
        return;
      }
      await _preferences!.save(result.idle, lockWhenHidden: result.hidden, captureAllowed: result.capture);
      if (!mounted) return;
      setState(() {
        _autoLockEnabled = result.idle;
        _lockWhenHidden = result.hidden;
      });
      _idleTimer?.cancel();
      _touchActivity();
    } catch (_) {
      if (result.capture != previousCapture && !WindowPrivacy.setCaptureAllowed(previousCapture)) {
        _notice(t.captureSettingFailed);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.vaultPreferencesSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _selectVault(String? id) async {
    if (_busy || _editing || _renamingVault || _catalog == null || id == _selectedVaultId) {
      return;
    }
    _lock();
    _master.clear();
    _confirmation.clear();
    _vaultName.clear();
    setState(() => _loading = true);
    try {
      _vaults = await _catalog!.list();
      VaultReference? selected;
      if (id == null) {
        selected = _vaults.isEmpty ? _catalog!.legacy : _catalog!.newVault();
        _vaults.add(selected);
      } else {
        selected = _vaults.where((v) => v.id == id).firstOrNull;
      }
      if (selected == null) {
        throw StateError('Selected vault is unavailable');
      }
      _selectedVaultId = selected.id;
      _store = selected.store;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'read';
          _selectedVaultId = null;
          _store = null;
        });
      }
    }
  }

  String _vaultSyncHelp() {
    final backup = widget.githubBackup!;
    final session = _session;
    if (!backup.isManual(_selectedVaultId)) return t.syncVaultHelp;
    final date = backup.lastVaultSync(_selectedVaultId);
    final state = session != null && backup.matchesLastSync(_selectedVaultId, session)
        ? t.syncLocalConfirmed
        : t.syncLocalPending;
    return '$state${date == null ? '' : '\n${t.syncVaultChecked(date: date.toLocal().toString().split('.').first)}'}\n${t.syncManualOnly}';
  }

  Future<void> _showHistory() async {
    if (_busy || _editing || _catalog == null) return;
    late List<({VaultReference vault, File file, DateTime date})> snapshots;
    try {
      snapshots = await _catalog!.history();
    } catch (_) {
      _notice(t.vaultReadFailed);
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<File>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.vaultHistory),
        content: SizedBox(
          width: 440,
          height: 340,
          child: Column(
            children: [
              Text(t.vaultHistoryHelp),
              const SizedBox(height: 12),
              Expanded(
                child: snapshots.isEmpty
                    ? Center(child: Text(t.vaultHistoryEmpty))
                    : ListView.builder(
                        itemCount: snapshots.length,
                        itemBuilder: (context, index) {
                          final item = snapshots[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                              title: Text(_vaultLabel(item.vault)),
                              subtitle: Text(
                                item.date.toLocal().toString().split('.').first,
                              ),
                              trailing: const Icon(Icons.restore_rounded),
                              onTap: () => Navigator.pop(context, item.file),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () => Navigator.pop(context),
            child: Text(t.githubClose),
          ),
        ],
      ),
    );
    if (selected != null && mounted) await _importVault(snapshot: selected);
  }

  Future<void> _showConflicts() async {
    final session = _session;
    if (_busy || _editing || session == null || session.isLocked) return;
    final epoch = _securityEpoch;
    final variants = session.entries.where((e) => e.conflictOf != null).toList();
    final revealed = <String>{};
    _sensitiveDialogOpen = true;
    final selected = await showDialog<VaultEntry>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(t.syncReviewConflicts),
          content: SizedBox(
            width: 460,
            height: 360,
            child: Column(
              children: [
                Text(t.syncReviewHelp),
                const SizedBox(height: 12),
                Expanded(
                  child: variants.isEmpty
                      ? Center(child: Text(t.syncNoConflicts))
                      : ListView(
                          children: [
                            for (final entry in variants)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: ExpansionTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  collapsedShape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  tilePadding: const EdgeInsets.all(12),
                                  childrenPadding: const EdgeInsets.all(12),
                                  title: Text(entry.title),
                                  subtitle: Text(
                                    t.syncVariant(
                                      id: entry.id.substring(
                                        0,
                                        entry.id.length < 12 ? entry.id.length : 12,
                                      ),
                                    ),
                                  ),
                                  children: [
                                    if (entry.isFile)
                                      Text(
                                        '${entry.attachments.single.name} · ${entry.attachments.single.size} B',
                                      )
                                    else ...[
                                      Text(entry.username),
                                      TextFormField(
                                        initialValue: entry.password,
                                        readOnly: true,
                                        enableInteractiveSelection: false,
                                        enableIMEPersonalizedLearning: false,
                                        obscureText: !revealed.contains(
                                          entry.id,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: t.vaultEntryPassword,
                                          suffixIcon: IconButton(
                                            tooltip: t.syncShowPassword,
                                            onPressed: () => update(() {
                                              if (!revealed.add(entry.id)) {
                                                revealed.remove(entry.id);
                                              }
                                            }),
                                            icon: Icon(
                                              revealed.contains(entry.id)
                                                  ? Icons.visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                            ),
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => widget.copySecret(entry.password),
                                        style: TextButton.styleFrom(padding: const EdgeInsets.all(12)),
                                        icon: const Icon(Icons.copy_rounded, size: 18),
                                        label: Text(t.copy),
                                      ),
                                      Text(entry.notes),
                                    ],
                                    const SizedBox(height: 12),
                                    FilledButton.tonal(
                                      onPressed: () => Navigator.pop(context, entry),
                                      child: Text(t.syncKeepVariant),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
              onPressed: () => Navigator.pop(context),
              child: Text(t.githubClose),
            ),
          ],
        ),
      ),
    );
    _sensitiveDialogOpen = false;
    if (selected == null || !mounted || epoch != _securityEpoch || session.isLocked) {
      return;
    }
    if (!await _confirm(t.syncKeepVariant, t.syncKeepVariantQuestion) ||
        !mounted ||
        epoch != _securityEpoch ||
        session.isLocked) {
      return;
    }
    await _persist([
      for (final e in session.entries)
        if (e.id == selected.id) e.withConflict(null) else if (e.conflictOf != selected.conflictOf) e,
    ]);
  }

  Future<void> _deleteVault() async {
    final store = _store;
    if (_busy || _editing || _renamingVault || !_exists || store == null) {
      return;
    }
    final epoch = _securityEpoch;
    final id = _selectedVaultId;
    final reference = _vaults.where((vault) => vault.id == id).firstOrNull;
    final name = _session?.name ?? (reference == null ? t.vaultLocal : _vaultLabel(reference));
    if (!await _confirm(
          t.vaultDeleteVault,
          t.vaultDeleteVaultQuestion(name: name),
        ) ||
        !mounted ||
        _busy ||
        epoch != _securityEpoch ||
        store != _store) {
      return;
    }
    _lock();
    final deletionEpoch = _securityEpoch;
    await _operation(() async {
      await store.delete(
        allowed: () => mounted && deletionEpoch == _securityEpoch && _store == store,
      );
      if (!mounted || _store != store) return;
      setState(() {
        _knownVaultNames.remove(id);
        _store = null;
        _selectedVaultId = null;
        _vaults = [];
        _exists = false;
        _loading = true;
      });
      await _load();
      if (mounted) _notice(t.vaultDeleted);
    });
  }

  String _vaultLabel(VaultReference vault) =>
      _knownVaultNames[vault.id] ??
      (vault.id == 'legacy' ? t.vaultPrimary : t.vaultIdentifier(id: vault.id.substring(0, 8)));

  Widget _folderSelector(VaultSession session) => LayoutBuilder(
    builder: (context, constraints) {
      final selectedName = session.folders
          .where((folder) => folder.id == _entryFolderId)
          .map((folder) => _locationName(session, folder))
          .firstOrNull;
      return PopupMenuButton<String>(
        key: ValueKey('entry-folder-${_editingId ?? 'new'}'),
        enabled: !_busy,
        tooltip: t.vaultLocation,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        borderRadius: BorderRadius.circular(12),
        constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
        onSelected: (value) => setState(() => _entryFolderId = value.isEmpty ? null : value),
        itemBuilder: (context) => [
          InsetMenuItem(
            value: '',
            label: t.vaultRoot,
            icon: Icons.folder_outlined,
            selected: _entryFolderId == null,
          ),
          for (final folder in session.folders)
            InsetMenuItem(
              value: folder.id,
              label: _locationName(session, folder),
              icon: Icons.folder_outlined,
              selected: _entryFolderId == folder.id,
            ),
        ],
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: t.vaultLocation,
            enabled: !_busy,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedName ?? t.vaultRoot,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more_rounded, size: 20),
            ],
          ),
        ),
      );
    },
  );

  String _locationName(VaultSession session, VaultFolder folder) {
    final parent = session.folders.where((item) => item.id == folder.parentId).firstOrNull;
    return parent == null ? folder.name : '${parent.name} / ${folder.name}';
  }

  Widget _vaultSwitcher() => PopupMenuButton<String>(
    key: const Key('vault-switcher'),
    tooltip: t.vaultChoose,
    enabled: !_busy,
    icon: const Icon(Icons.expand_more_rounded, size: 21),
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    onSelected: (id) => switch (id) {
      'import' => _importVault(),
      'delete' => _deleteVault(),
      'history' => _showHistory(),
      'conflicts' => _showConflicts(),
      _ => _selectVault(id == 'new' ? null : id),
    },
    itemBuilder: (_) => [
      for (final vault in _vaults)
        InsetMenuItem(
          value: vault.id,
          label: _vaultLabel(vault),
          icon: vault.id == _selectedVaultId ? Icons.check_rounded : Icons.lock_outline_rounded,
          selected: vault.id == _selectedVaultId,
        ),
      const PopupMenuDivider(),
      InsetMenuItem(
        key: const Key('new-vault'),
        value: 'new',
        label: t.vaultNew,
        icon: Icons.add_rounded,
      ),
      InsetMenuItem(
        value: 'import',
        label: t.vaultImport,
        icon: Icons.file_open_outlined,
      ),
      InsetMenuItem(
        value: 'history',
        label: t.vaultHistory,
        icon: Icons.history_rounded,
      ),
      if (_session != null && !_editing)
        InsetMenuItem(
          value: 'conflicts',
          label: t.syncReviewConflicts,
          icon: Icons.difference_outlined,
        ),
      if (_exists && !_editing && !_renamingVault) ...[
        const PopupMenuDivider(),
        InsetMenuItem(
          key: const Key('delete-vault'),
          value: 'delete',
          label: t.vaultDeleteVault,
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    ],
  );

  void _clearEditor() {
    _draft.clear();
    _editingSsh = false;
    _editingId = null;
    _entryFolderId = null;
    _editing = false;
  }

  void _edit([
    VaultEntry? entry,
    String? folderId,
    bool ssh = false,
  ]) => setState(() {
    _error = null;
    _editingId = entry?.id;
    _editingSsh = entry?.isSsh ?? ssh;
    _draft.sshHost.text = entry?.ssh?.host ?? '';
    _draft.sshPort.text = (entry?.ssh?.port ?? 22).toString();
    _draft.title.text = entry?.title ?? '';
    _draft.username.text = entry?.username ?? '';
    _draft.password.text =
        entry?.password ??
        _generator.generate(
          length: _generationLength,
          symbols: _generationSymbols,
        );
    if (entry != null && entry.password.isNotEmpty) {
      _generationLength = entry.password.characters.length.clamp(12, 64);
    }
    if (_editingSsh && entry == null) _draft.password.clear();
    _draft.notes.text = entry?.notes ?? '';
    _entryFolderId = entry != null ? entry.folderId : folderId;
    _editing = true;
  });

  Future<void> _passwordOptions() async {
    if (_busy) return;
    final options = await showDialog<PasswordOptions>(
      context: context,
      builder: (_) => PasswordOptionsDialog(
        options: (length: _generationLength, symbols: _generationSymbols),
      ),
    );
    if (!mounted || options == null || !_editing || _session == null || _busy) {
      return;
    }
    setState(() {
      _generationLength = options.length;
      _generationSymbols = options.symbols;
      _draft.password.text = _generator.generate(
        length: _generationLength,
        symbols: _generationSymbols,
      );
    });
  }

  Future<void> _save() async {
    try {
      await _saveEntry();
    } on MemoryProtectionException {
      if (mounted) setState(() => _error = 'memory-protection');
    }
  }

  Future<void> _saveEntry() async {
    if (_busy) return;
    if (_draft.title.text.trim().isEmpty) {
      setState(() => _error = 'title');
      return;
    }
    SshEndpoint? endpoint;
    if (_editingSsh) {
      endpoint = SshEndpoint(
        host: _draft.sshHost.text.trim().toLowerCase(),
        port: int.tryParse(_draft.sshPort.text) ?? 0,
      );
      if (!endpoint.isValid ||
          !SshEndpoint.validUsername(_draft.username.text) ||
          !SshEndpoint.validPassword(_draft.password.text)) {
        setState(() => _error = 'ssh-invalid');
        return;
      }
    }
    final session = _session!;
    final entry = _editingId == null
        ? VaultEntry.create(
            title: _draft.title.text,
            username: _draft.username.text,
            password: _draft.password.text,
            notes: _draft.notes.text,
            folderId: _entryFolderId,
            ssh: endpoint,
          )
        : VaultEntry(
            id: _editingId!,
            kind: _editingSsh ? VaultEntryKind.ssh : VaultEntryKind.text,
            title: _draft.title.text,
            username: _draft.username.text,
            password: _draft.password.text,
            notes: _draft.notes.text,
            folderId: _entryFolderId,
            ssh: endpoint,
          );
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    final entries = organization.entries;
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) {
      organization.appendEntries([entry], entry.folderId);
    } else {
      final previous = entries[index];
      entries[index] = entry.withConflict(previous.conflictOf).atPosition(entry.folderId, previous.order);
      if (previous.folderId != entry.folderId) organization.move(VaultItem.entry(entry), entry.folderId);
    }
    if (await _persist(entries, folders: organization.folders) && mounted) {
      setState(() {
        _collapsedFolders.remove(entry.folderId ?? '');
        _clearEditor();
      });
    }
  }

  Future<bool> _persist(
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store!.save(session, entries, folders: folders, name: name);
      if (!mounted || _session != session || session.isLocked) return false;
      if (_selectedVaultId != null && session.name != null) {
        _knownVaultNames[_selectedVaultId!] = session.name!;
      }
      return true;
    } on VaultConflictException {
      if (mounted && _session == session) setState(() => _error = 'conflict');
    } on VaultFormatException {
      if (mounted && _session == session) setState(() => _error = 'limit');
    } on MemoryProtectionException {
      if (mounted && _session == session) {
        setState(() => _error = 'memory-protection');
      }
    } catch (_) {
      if (mounted && _session == session) setState(() => _error = 'io');
    } finally {
      if (mounted && _session == session) setState(() => _busy = false);
    }
    return false;
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton(
              key: const Key('confirm-delete'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.vaultDelete),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteEntry(VaultEntry entry) async {
    if (_busy) return;
    final session = _session;
    if (!await _confirm(
          entry.isFile ? t.vaultDeleteFile : t.vaultDeleteEntry,
          t.vaultDeleteEntryQuestion(name: entry.title),
        ) ||
        !mounted ||
        session != _session ||
        session == null ||
        session.isLocked) {
      return;
    }
    if (await _persist(
      session.entries.where((e) => e.id != entry.id).toList(),
    )) {
      _viewers.close(entry.id);
      await widget.clearClipboard();
      if (mounted && _editingId == entry.id) setState(_clearEditor);
    }
  }

  void _startRenameVault() {
    if (_busy || _session == null) return;
    setState(() {
      _renameName.text = _session!.name ?? t.vaultLocal;
      _renameName.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _renameName.text.length,
      );
      _renamingVault = true;
      _renameInvalid = false;
    });
  }

  Future<void> _renameVault() async {
    final session = _session;
    if (_busy || session == null) return;
    final name = _renameName.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _renameInvalid = true);
      return;
    }
    if (await _persist(session.entries, name: name) && mounted) {
      setState(() {
        _renamingVault = false;
        _renameName.clear();
      });
    }
  }

  Future<void> _nameFolder({VaultFolder? folder, String? parentId}) async {
    final session = _session;
    if (_busy || session == null) return;
    if (folder == null && session.folders.length >= VaultCipher.maxFolders) {
      setState(() => _error = 'limit');
      return;
    }
    parentId = folder?.parentId ?? parentId;
    final isSection = parentId == null;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => VaultNameDialog(
        title: folder == null
            ? (isSection ? t.vaultNewFolder : t.vaultNewSubfolder)
            : (isSection ? t.vaultRenameFolder : t.vaultRenameSubfolder),
        label: isSection ? t.vaultFolderName : t.vaultSubfolderName,
        initialValue: folder?.name ?? '',
        existingNames: session.folders
            .where((f) => f.id != folder?.id && f.parentId == parentId)
            .map((f) => f.name)
            .toList(),
      ),
    );
    if (!mounted || name == null || _session != session || session.isLocked) {
      return;
    }
    final changed = folder == null
        ? VaultFolder.create(name, parentId: parentId)
        : VaultFolder(id: folder.id, name: name, parentId: parentId, order: folder.order);
    final folders = [...session.folders];
    final index = folders.indexWhere((f) => f.id == changed.id);
    if (index < 0) {
      folders.add(changed);
    } else {
      folders[index] = changed;
    }
    final organization = VaultOrganization(entries: session.entries, folders: folders);
    if (folder == null) organization.move(VaultItem.folder(changed), parentId);
    if (await _persist(organization.entries, folders: organization.folders) && mounted) {
      setState(() {
        _collapsedFolders.remove(changed.id);
        _collapsedFolders.remove(parentId);
      });
    }
  }

  Future<void> _deleteFolder(VaultFolder folder) async {
    final session = _session;
    if (_busy || session == null) return;
    if (!await _confirm(
          folder.isSection ? t.vaultDeleteFolder : t.vaultDeleteSubfolder,
          folder.isSection
              ? t.vaultDeleteFolderQuestion(name: folder.name)
              : t.vaultDeleteSubfolderQuestion(name: folder.name),
        ) ||
        !mounted ||
        _session != session ||
        session.isLocked) {
      return;
    }
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    organization.deleteFolder(folder);
    if (await _persist(
          organization.entries,
          folders: organization.folders,
        ) &&
        mounted) {
      setState(() {
        _collapsedFolders.remove(folder.id);
        _collapsedFolders.remove('');
      });
    }
  }

  Future<void> _moveItem(
    VaultItem item,
    String? folderId,
    String? beforeKey,
  ) async {
    final session = _session;
    if (_busy ||
        session == null ||
        session.isLocked ||
        (folderId != null && !session.folders.any((f) => f.id == folderId))) {
      return;
    }
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    if (!organization.canMove(item, folderId)) return;
    if (beforeKey != null && organization.children(folderId).every((child) => child.key != beforeKey)) return;
    organization.move(item, folderId, beforeKey: beforeKey);
    if (await _persist(organization.entries, folders: organization.folders) && mounted) {
      setState(() => _collapsedFolders.remove(folderId ?? ''));
    }
  }

  void _lock() {
    _sshConnections.revoke();
    if (_sensitiveDialogOpen && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _sensitiveDialogOpen = false;
    }
    _viewers.closeAll();
    _securityEpoch++;
    _master.clear();
    _confirmation.clear();
    _vaultName.clear();
    _idleTimer?.cancel();
    _copyNoticeTimer?.cancel();
    _copyNotice = null;
    _treeKey.currentState?.stopDragging();
    _session?.lock();
    unawaited(widget.clearClipboard());
    setState(() {
      _session = null;
      _busy = false;
      _clearEditor();
      _error = null;
      _collapsedFolders.clear();
      _renamingVault = false;
      _renameName.clear();
    });
  }

  @override
  void dispose() {
    _sshConnections.dispose();
    _copyNoticeTimer?.cancel();
    _copyNotice = null;
    _viewers.closeAll();
    _securityEpoch++;
    _systemLock.setMethodCallHandler(null);
    _idleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyActivity);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerActivity);
    _treeKey.currentState?.stopDragging();
    _session?.lock();
    for (final controller in [
      _master,
      _vaultName,
      _renameName,
      _confirmation,
    ]) {
      controller.clear();
      controller.dispose();
    }
    _draft.dispose();
    super.dispose();
  }

  String get _errorText => switch (_error) {
    'ssh-invalid' => t.sshInvalid,
    'required' => t.vaultPasswordRequired,
    'mismatch' => t.vaultPasswordMismatch,
    'password-policy' => t.vaultPasswordRequirements,
    'memory-protection' => t.vaultMemoryProtectionFailed,
    'unlock' => t.vaultUnlockFailed,
    'format' => t.vaultFormatFailed,
    'conflict' => t.vaultConflict,
    'title' => t.vaultTitleRequired,
    'limit' => t.vaultLimit,
    'read' => t.vaultReadFailed,
    _ => t.vaultWriteFailed,
  };

  Widget _folderTree(VaultSession session) => _VaultTree(
    key: _treeKey,
    session: session,
    busy: _busy,
    collapsed: _collapsedFolders,
    entryCard: _entryCard,
    createFolder: (parentId) => _nameFolder(parentId: parentId),
    renameFolder: (folder) => _nameFolder(folder: folder),
    deleteFolder: _deleteFolder,
    addEntry: (parentId) => _edit(null, parentId),
    addFile: _addFile,
    addSsh: (parentId) => _edit(null, parentId, true),
    createTextFile: _createTextFile,
    move: _moveItem,
  );

  Future<void> _copyEntry(VaultEntry entry) async {
    final session = _session;
    if (session == null || session.isLocked || _busy) return;
    final copied = await widget.copySecret(entry.password);
    if (mounted && copied && _session == session && !session.isLocked) {
      _copyNoticeTimer?.cancel();
      setState(() => _copyNotice = (session: session, entryId: entry.id));
      _copyNoticeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copyNotice = null);
      });
    }
  }

  Widget _entryCard(VaultEntry entry) {
    final card = _VaultEntryCard(
      entry: entry,
      copied: _copyNotice == (session: _session, entryId: entry.id),
      key: ValueKey('entry-card-${entry.id}'),
      onTap: _busy
          ? null
          : entry.isFile
          ? () => _openFile(entry)
          : entry.isSsh
          ? () => _connectSsh(entry)
          : !entry.hasPassword
          ? null
          : () => _copyEntry(entry),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey(
              '${entry.isFile ? 'export-file' : 'edit-entry'}-${entry.id}',
            ),
            tooltip: entry.isFile ? t.vaultSaveAttachment : t.vaultEditEntry,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            visualDensity: VisualDensity.standard,
            padding: const EdgeInsets.all(8),
            onPressed: _busy
                ? null
                : entry.isFile
                ? () => _extractAttachment(entry.attachments.single)
                : () => _edit(entry),
            icon: Icon(
              entry.isFile ? Icons.save_alt_rounded : Icons.edit_outlined,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey('delete-entry-${entry.id}'),
            tooltip: entry.isFile ? t.vaultDeleteFile : t.vaultDeleteEntry,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            visualDensity: VisualDensity.standard,
            padding: const EdgeInsets.all(8),
            onPressed: _busy ? null : () => _deleteEntry(entry),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
    return Tooltip(
      message: entry.isFile
          ? t.vaultFileHint
          : entry.isSsh
          ? t.sshConnect
          : t.vaultEntryHint,
      child: card,
    );
  }

  String get _heading {
    if (_session case final session?) return session.name ?? t.vaultLocal;
    return _exists ? t.vaultLocked : t.emptyVault;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final session = _session;
    return SensitiveClipboardScope(
      copy: widget.copySecret,
      child: Listener(
        onPointerDown: (_) => _touchActivity(),
        onPointerHover: (_) => _touchActivity(),
        onPointerSignal: (_) => _touchActivity(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VaultHeader(
              title: _heading,
              unlocked: session != null,
              renaming: _renamingVault,
              renameName: _renameName,
              busy: _busy,
              renameInvalid: _renameInvalid,
              savingPreferences: _savingPreferences,
              showSettings: _editing == false && _renamingVault == false,
              switcher: _catalog != null && _editing == false && _renamingVault == false ? _vaultSwitcher() : null,
              onRename: _renameVault,
              onStartRename: _startRenameVault,
              onCancelRename: () => setState(() {
                _renamingVault = false;
                _renameName.clear();
              }),
              onSettings: _showPreferences,
              onLock: _lock,
            ),
            const SizedBox(height: 12),
            if (_error == 'read') ...[
              Text(_errorText),
              TextButton(onPressed: _load, child: Text(t.retry)),
            ] else if (session == null) ...[
              _VaultUnlockForm(
                exists: _exists,
                busy: _busy,
                vaultName: _vaultName,
                master: _master,
                confirmation: _confirmation,
                onOpen: _open,
              ),
            ] else if (_editing) ...[
              _VaultEntryEditor(
                draft: _draft,
                busy: _busy,
                isSsh: _editingSsh,
                locationSelector: _folderSelector(session),
                onSave: _save,
                onCancel: () => setState(() {
                  _clearEditor();
                  _error = null;
                }),
                onDelete: _editingId == null
                    ? null
                    : () => _deleteEntry(
                        session.entries.firstWhere((entry) => entry.id == _editingId),
                      ),
                onPasswordOptions: _passwordOptions,
                onGenerate: () => setState(() {
                  _draft.password.text = _generator.generate(length: _generationLength, symbols: _generationSymbols);
                }),
              ),
            ] else ...[
              _folderTree(session),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('add-entry'),
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: Text(t.vaultAddEntry),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('add-ssh'),
                onPressed: _busy ? null : () => _edit(null, null, true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.terminal_rounded, size: 20),
                label: Text(t.sshAdd),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('add-file'),
                onPressed: _busy ? null : _addFile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                label: Text(t.vaultAddFile),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('new-text-file'),
                onPressed: _busy ? null : _createTextFile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.note_add_outlined, size: 20),
                label: Text(t.vaultCreateTextFile),
              ),
              const SizedBox(height: 12),
              Text(
                widget.githubBackup?.signedIn == true ? _vaultSyncHelp() : t.vaultLocalOnly,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_busy && !_waitingForPassword)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null && _error != 'read')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _errorText,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
