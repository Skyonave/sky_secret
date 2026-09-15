import '../shared/desktop_tooltip.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/crypto.dart';
import '../../core/desktop/desktop_actions.dart';
import '../../core/desktop/clipboard/sensitive_clipboard.dart';
import '../../core/desktop/clipboard/sensitive_clipboard_boundary.dart';
import '../../core/desktop/clipboard/sensitive_clipboard_controller.dart';
import '../../core/settings/vault_preferences.dart';
import '../../core/os/windows/windows_sensitive_clipboard.dart';
import '../../core/sync/github/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../github/github_dialog.dart';
import '../settings/shortcut_dialog.dart';
import '../shared/app_theme.dart';

import '../generator/generator_service.dart';
import '../../core/settings/generator_preferences.dart';
import '../shared/desktop_menu.dart';
import '../shared/native_file_drop_target.dart';
import '../shared/input/sensitive_text_editing.dart';
import '../vault/vault_panel.dart';

class ManagerWindow extends StatefulWidget {
  final DesktopActions desktop;
  final SensitiveClipboard? clipboard;
  final SensitiveClipboardBoundary? clipboardBoundary;
  final VaultStore? vaultStore;
  final VaultCatalog? vaultCatalog;
  final VaultPreferences? vaultPreferences;
  final GitHubBackup? githubBackup;

  const ManagerWindow({
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
  State<ManagerWindow> createState() => _ManagerWindowState();
}

class _ManagerWindowState extends State<ManagerWindow> {
  final _vaultKey = GlobalKey<VaultPanelState>();
  bool _fileHover = false;
  late final _generatorService = GeneratorService(
    widget.vaultStore == null ? GeneratorPreferences.local() : GeneratorPreferences(),
  );
  bool _copying = false;

  late final _clipboard = SensitiveClipboardController(
    clipboard: widget.clipboard ?? WindowsSensitiveClipboard(),
    onCleared: () {},
  );
  void _beforeHide() {
    DesktopTooltip.dismissAll();
    DesktopMenuObserver.dismissAll();
    _clipboard.cancelPendingWrites();
    _vaultKey.currentState?.onWindowHidden();
  }

  void _afterShow() => _vaultKey.currentState?.onWindowShown();

  @override
  void initState() {
    super.initState();
    widget.clipboardBoundary?.attach(_copySecret);
    widget.desktop.onBeforeHide = _beforeHide;
    widget.desktop.onAfterShow = _afterShow;
  }

  @override
  void didUpdateWidget(ManagerWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clipboardBoundary != widget.clipboardBoundary) {
      oldWidget.clipboardBoundary?.detach(_copySecret);
      widget.clipboardBoundary?.attach(_copySecret);
    }
    if (oldWidget.desktop != widget.desktop) {
      oldWidget.desktop.onBeforeHide = null;
      oldWidget.desktop.onAfterShow = null;
      widget.desktop.onBeforeHide = _beforeHide;
      widget.desktop.onAfterShow = _afterShow;
    }
  }

  void _setFileHover(bool hovering) {
    if (!hovering) _vaultKey.currentState?.updateFileDropPosition(null);
    widget.desktop.setFileDragHover(hovering);
    if (!mounted || _fileHover == hovering) return;
    _fileHover = hovering;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _receiveFiles(List<String> paths) async {
    final vault = _vaultKey.currentState;
    final token = vault?.fileDropSession;
    final folderId = vault?.fileDropFolderId;
    _setFileHover(false);
    if (vault == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    try {
      if (!await widget.desktop.focusFileDrop() || !mounted) return;

      await vault.importDroppedFiles(paths, sessionToken: token, folderId: folderId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultDropReadFailed)));
      }
    }
  }

  Widget _fileDropTarget(Widget child) => NativeFileDropTarget(
    key: const Key('vault-file-drop'),
    enable: ModalRoute.of(context)?.isCurrent ?? true,
    onHover: _setFileHover,
    onPosition: (position) {
      _vaultKey.currentState?.updateFileDropPosition(position);
    },
    onFiles: (paths) => unawaited(_receiveFiles(paths)),
    onRejected: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultDropReadFailed))),
    onUnavailable: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultDropUnavailable))),
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (_fileHover && !(_vaultKey.currentState?.canAcceptFileDrop ?? false))
          Positioned.fill(
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  key: const Key('vault-file-drop-overlay'),
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xF513212D),
                    border: Border.all(color: AppColors.accent, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.file_download_outlined,
                        color: AppColors.accent,
                        size: 38,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.vaultDropTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _vaultKey.currentState?.fileDropHint ?? t.vaultDropLocked,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Future<bool> _copySecret(String value) async {
    if (_copying) return false;
    setState(() => _copying = true);
    try {
      if (await _clipboard.write(value) == false) return false;

      return true;
    } on ClipboardUnavailable {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.clipboardBusy)));
      }
      return false;
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _clearVaultClipboard() => _clipboard.clear();

  @override
  void dispose() {
    widget.clipboardBoundary?.detach(_copySecret);
    widget.desktop.onBeforeHide = null;
    widget.desktop.onAfterShow = null;
    widget.desktop.setFileDragHover(false);
    _clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SensitiveClipboardScope(
    copy: _copySecret,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(widget.desktop.hide()),
      },
      child: Focus(
        autofocus: true,
        child: _fileDropTarget(
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _titleBar(),
                  Expanded(
                    child: VaultPanel(
                      generatorService: _generatorService,
                      onFileDragChanged: widget.desktop.setFileDragActive,
                      onSearchHandlerChanged: widget.desktop.setSearchHandler,
                      searchShortcut: () => widget.desktop.searchShortcut,
                      onCodesBlur: widget.desktop.onCompanionBlur,
                      key: _vaultKey,
                      store: widget.vaultStore,
                      catalog: widget.vaultCatalog,
                      preferences: widget.vaultPreferences,
                      githubBackup: widget.githubBackup,
                      copySecret: _copySecret,
                      clearClipboard: _clearVaultClipboard,
                      onSearchDismissed: widget.desktop.hide,
                      onSshAuthorizationChanged: widget.desktop.setSshAuthenticationPending,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.desktop,
                    builder: (context, _) => widget.desktop.notice == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            child: Text(
                              widget.desktop.notice!,
                              style: const TextStyle(color: Color(0xFFFFCB8A), fontSize: 11),
                            ),
                          ),
                  ),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _titleBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => unawaited(widget.desktop.drag()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(t.appName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        DesktopIconButton(
          tooltip: t.hide,
          onPressed: () => unawaited(widget.desktop.hide()),
          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
        ),
      ],
    ),
  );

  ButtonStyle get _footerButtonStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    foregroundColor: AppColors.muted,
    textStyle: const TextStyle(fontSize: 11),
  );

  Widget _githubStatus(String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: switch (widget.githubBackup?.status) {
            BackupStatus.synced => const Color(0xFF75D9A0),
            BackupStatus.pending || BackupStatus.working => const Color(0xFFFFCB8A),
            BackupStatus.failed || BackupStatus.conflict => const Color(0xFFFF8F8F),
            _ => AppColors.muted,
          },
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );

  Widget _syncButton() => ListenableBuilder(
    listenable: widget.githubBackup!,
    builder: (context, _) {
      final backup = widget.githubBackup!;
      return DesktopTooltip(
        message: backup.busy ? t.syncWorking : t.syncNow,
        child: TextButton.icon(
          key: const Key('synchronize-vault'),
          style: _footerButtonStyle,
          onPressed: backup.busy || !backup.usable
              ? null
              : () {
                  unawaited(_vaultKey.currentState?.synchronize(backup));
                },
          icon: backup.busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded, size: 15),
          label: Text(t.desktopSync),
        ),
      );
    },
  );

  Widget _footer() => Container(
    key: const Key('manager-footer'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: widget.githubBackup == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DefaultTextStyle(
                    style: const TextStyle(fontFamily: 'Segoe UI', color: AppColors.muted, fontSize: 11),
                    child: _githubStatus(t.githubDisconnected),
                  ),
                )
              : ListenableBuilder(
                  listenable: widget.githubBackup!,
                  builder: (context, _) => DesktopTooltip(
                    message: githubStatusLabel(widget.githubBackup!),
                    child: TextButton(
                      style: _footerButtonStyle,
                      onPressed: () => _vaultKey.currentState?.showGitHub(widget.githubBackup!),
                      child: _githubStatus(githubStatusLabel(widget.githubBackup!)),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 4),
        if (widget.githubBackup != null) _syncButton(),
        const SizedBox(width: 4),
        DesktopIconButton(
          key: const Key('shortcut-settings'),
          tooltip: t.keyboardShortcuts,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ShortcutDialog(desktop: widget.desktop),
          ),
          icon: const Icon(Icons.keyboard_outlined, size: 17, color: AppColors.muted),
        ),
      ],
    ),
  );
}
