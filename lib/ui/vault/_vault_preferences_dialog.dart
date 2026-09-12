part of 'vault_panel.dart';

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
    insetPadding: const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 24,
    ),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
    contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    scrollable: true,
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('auto-lock-switch'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.only(left: 14, right: 8),
              title: Text(
                t.vaultAutoLock,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              t.vaultAutoLockHelp,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('lock-when-hidden-switch'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              title: Text(t.vaultLockWhenHidden),
              value: hidden,
              onChanged: (value) => setState(() => hidden = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              t.vaultLockWhenHiddenHelp,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('screen-capture-switch'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              title: Text(t.captureVisible),
              value: captureAllowed,
              onChanged: (value) => setState(() => captureAllowed = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              t.captureVisibleHelp,
              style: TextStyle(fontSize: 12, height: 1.45, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          if (widget.canManageVault) ...[
            const SizedBox(height: 20),
            _settingsAction(
              key: 'export-vault',
              label: t.vaultExport,
              icon: Icons.ios_share_rounded,
              onPressed: widget.busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onExport();
                    },
            ),
            const SizedBox(height: 8),
            _settingsAction(
              key: 'change-master',
              label: t.vaultChangePassword,
              icon: Icons.key_outlined,
              onPressed: widget.busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onChangePassword();
                    },
            ),
          ],
        ],
      ),
    ),
    actions: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(t.cancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('save-vault-preferences'),
              onPressed: () => Navigator.pop(context, (idle: enabled, hidden: hidden, capture: captureAllowed)),
              child: Text(t.save),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _settingsAction({
    required String key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: Key(key),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        foregroundColor: colors.onSurface,
        overlayColor: colors.primary.withValues(alpha: 0.08),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
