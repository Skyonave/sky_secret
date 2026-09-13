import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/crypto.dart';
import '../../core/desktop/desktop_actions.dart';
import '../../core/desktop/clipboard/sensitive_clipboard.dart';
import '../../core/desktop/clipboard/sensitive_clipboard_boundary.dart';
import '../../core/settings/shortcut_settings.dart';
import '../../core/settings/vault_preferences.dart';
import '../../core/os/windows/windows_sensitive_clipboard.dart';
import '../../core/sync/github/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../github/github_dialog.dart';
import '../settings/shortcut_dialog.dart';
import '../shared/app_theme.dart';
import '../shared/native_file_drop_target.dart';
import '../shared/input/sensitive_text_editing.dart';
import '../vault/vault_panel.dart';

part '_generator_panel.dart';

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
  final _generator = PasswordGenerator();
  int _page = 0;
  int _length = 24;
  bool _symbols = true;
  String _password = '';
  bool _copied = false;
  Timer? _clipboardTimer;
  int? _clipboardRevision;
  bool _copying = false;
  int _clipboardGeneration = 0;
  late final SensitiveClipboard _clipboard = widget.clipboard ?? WindowsSensitiveClipboard();

  void _beforeHide() => _vaultKey.currentState?.onWindowHidden();

  @override
  void initState() {
    super.initState();
    widget.clipboardBoundary?.attach(_copySecret);
    widget.desktop.onBeforeHide = _beforeHide;
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
      widget.desktop.onBeforeHide = _beforeHide;
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
      _selectPage(0);
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
      if (_page == 0) _vaultKey.currentState?.updateFileDropPosition(position);
    },
    onFiles: (paths) => unawaited(_receiveFiles(paths)),
    onRejected: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultDropReadFailed))),
    onUnavailable: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultDropUnavailable))),
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (_fileHover && !(_page == 0 && (_vaultKey.currentState?.canAcceptFileDrop ?? false)))
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

  void _selectPage(int page) => setState(() {
    _page = page;
    if (page == 1 && _password.isEmpty) _generate();
  });

  void _generate() {
    _password = _generator.generate(length: _length, symbols: _symbols);
    _copied = false;
  }

  Future<void> _copy() => _copySecret(_password, generated: true);

  Future<bool> _copySecret(String value, {bool generated = false}) async {
    if (_copying) return false;
    final generation = _clipboardGeneration;
    setState(() => _copying = true);
    try {
      _clipboardRevision = await _clipboard.write(value);
      _clipboardTimer?.cancel();
      if (!mounted || generation != _clipboardGeneration) {
        await _clearClipboard();
        return false;
      }
      _clipboardTimer = Timer(const Duration(seconds: 30), _clearClipboard);
      if (mounted) setState(() => _copied = generated && _password == value);
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

  Future<void> _clearClipboard() async {
    final owned = _clipboardRevision;
    if (owned == null) return;
    try {
      await _clipboard.clearIfCurrent(owned);
    } on ClipboardUnavailable {
      if (mounted && _clipboardRevision == owned) {
        _clipboardTimer = Timer(const Duration(seconds: 1), _clearClipboard);
      }
      return;
    }
    if (_clipboardRevision != owned) return;
    _clipboardRevision = null;
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _clearVaultClipboard() async {
    _clipboardGeneration++;
    _clipboardTimer?.cancel();
    await _clearClipboard();
  }

  @override
  void dispose() {
    widget.clipboardBoundary?.detach(_copySecret);
    widget.desktop.onBeforeHide = null;
    widget.desktop.setFileDragHover(false);
    _clipboardGeneration++;
    _clipboardTimer?.cancel();
    unawaited(_clearClipboard());
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 430;
                        return SingleChildScrollView(
                          key: const Key('manager-content'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _tabs(),
                              SizedBox(height: compact ? 8 : 16),
                              Offstage(
                                offstage: _page != 0,
                                child: VaultPanel(
                                  active: _page == 0,
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
                              if (_page == 1)
                                _GeneratorPanel(
                                  compact: compact,
                                  password: _password,
                                  length: _length,
                                  symbols: _symbols,
                                  copied: _copied,
                                  copying: _copying,
                                  onCopy: _copy,
                                  onRegenerate: () => setState(_generate),
                                  onLengthChanged: (value) => setState(() => _length = value.round()),
                                  onSymbolsChanged: (value) => setState(() {
                                    _symbols = value;
                                    _generate();
                                  }),
                                ),
                              ListenableBuilder(
                                listenable: widget.desktop,
                                builder: (context, _) {
                                  final notice = widget.desktop.notice;
                                  if (notice == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      notice,
                                      style: const TextStyle(
                                        color: Color(0xFFFFCB8A),
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (widget.githubBackup != null) _syncBar(),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _titleBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => unawaited(widget.desktop.drag()),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  t.appName,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: t.hide,
          onPressed: () => unawaited(widget.desktop.hide()),
          icon: const Icon(Icons.close_rounded, size: 19, color: AppColors.muted),
        ),
      ],
    ),
  );

  Widget _tabs() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        _tab(0, Icons.inventory_2_outlined, t.vault),
        _tab(1, Icons.auto_awesome_outlined, t.generator),
      ],
    ),
  );

  Widget _tab(
    int page,
    IconData icon,
    String label,
  ) => Expanded(
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: _page == page ? AppColors.accent : AppColors.muted,
        backgroundColor: _page == page ? const Color(0xFF1B3A4B) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onPressed: () => _selectPage(page),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );

  ButtonStyle get _footerButtonStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 36),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    foregroundColor: AppColors.muted,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
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
      const SizedBox(width: 8),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );

  Widget _syncBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
    child: ListenableBuilder(
      listenable: widget.githubBackup!,
      builder: (context, _) {
        final backup = widget.githubBackup!;
        return SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            key: const Key('synchronize-vault'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: backup.busy || !backup.usable
                ? null
                : () {
                    if (_vaultKey.currentState?.fileDropSession == null) {
                      setState(() => _page = 0);
                    }
                    unawaited(_vaultKey.currentState?.synchronize(backup));
                  },
            icon: backup.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 20),
            label: Text(backup.busy ? t.syncWorking : t.syncNow),
          ),
        );
      },
    ),
  );

  Widget _footer() => Container(
    key: const Key('manager-footer'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: widget.githubBackup == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      child: _githubStatus(t.githubDisconnected),
                    ),
                  )
                : ListenableBuilder(
                    listenable: widget.githubBackup!,
                    builder: (context, _) => Tooltip(
                      message: githubStatusLabel(widget.githubBackup!),
                      child: TextButton(
                        style: _footerButtonStyle,
                        onPressed: () => _vaultKey.currentState?.showGitHub(
                          widget.githubBackup!,
                        ),
                        child: _githubStatus(
                          githubStatusLabel(widget.githubBackup!),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ListenableBuilder(
              listenable: widget.desktop,
              builder: (context, _) => TextButton(
                key: const Key('shortcut-settings'),
                style: _footerButtonStyle,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ShortcutDialog(desktop: widget.desktop),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune_rounded, size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        shortcutLabel(widget.desktop.shortcut),
                        overflow: TextOverflow.ellipsis,
                      ),
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
}
