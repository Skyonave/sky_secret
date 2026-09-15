part of '../vault_panel.dart';

class _VaultPreferencesDialog extends StatefulWidget {
  final bool autoLockEnabled;
  final bool lockWhenHidden;
  final bool captureAllowed;
  final bool canManageVault;
  final bool busy;
  final VoidCallback onExport;
  final VoidCallback onChangePassword;

  const _VaultPreferencesDialog({
    required this.autoLockEnabled,
    required this.lockWhenHidden,
    required this.captureAllowed,
    required this.canManageVault,
    required this.busy,
    required this.onExport,
    required this.onChangePassword,
  });

  @override
  State<_VaultPreferencesDialog> createState() => _VaultPreferencesDialogState();
}

class _VaultPreferencesDialogState extends State<_VaultPreferencesDialog> {
  late bool enabled = widget.autoLockEnabled;
  late bool hidden = widget.lockWhenHidden;
  late bool captureAllowed = widget.captureAllowed;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.vaultSettings),
    insetPadding: const EdgeInsets.all(20),
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    scrollable: true,
    content: SizedBox(
      width: 356,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopOption(
            key: const Key('auto-lock-switch'),
            title: t.vaultAutoLock,
            description: t.vaultAutoLockHelp,
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
          ),
          const SizedBox(height: 4),
          DesktopOption(
            key: const Key('lock-when-hidden-switch'),
            title: t.vaultLockWhenHidden,
            description: t.vaultLockWhenHiddenHelp,
            value: hidden,
            onChanged: (value) => setState(() => hidden = value),
          ),
          const SizedBox(height: 4),
          DesktopOption(
            key: const Key('screen-capture-switch'),
            title: t.captureVisible,
            description: t.captureVisibleHelp,
            value: captureAllowed,
            onChanged: (value) => setState(() => captureAllowed = value),
          ),
          if (widget.canManageVault) ...[
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Divider(height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('export-vault'),
                    onPressed: widget.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onExport();
                          },
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: Text(t.vaultExport),
                  ),
                  OutlinedButton.icon(
                    key: const Key('change-master'),
                    onPressed: widget.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onChangePassword();
                          },
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: Text(t.vaultChangePassword),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
      FilledButton(
        key: const Key('save-vault-preferences'),
        onPressed: () => Navigator.pop(context, (idle: enabled, hidden: hidden, capture: captureAllowed)),
        child: Text(t.save),
      ),
    ],
  );
}
