part of '../vault_panel.dart';

class _VaultEntryEditor extends StatelessWidget {
  final VaultEntryController draft;
  final bool busy;
  final bool isSsh;
  final Widget locationSelector;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final VoidCallback onPasswordOptions;
  final VoidCallback onGenerate;

  const _VaultEntryEditor({
    required this.draft,
    required this.busy,
    required this.isSsh,
    required this.locationSelector,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
    required this.onPasswordOptions,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: locationSelector,
      ),
      _field(draft.title, t.vaultEntryTitle, 'entry-title'),
      if (isSsh) ...[
        _field(draft.sshHost, t.sshHost, 'ssh-host'),
        _field(draft.sshPort, t.sshPort, 'ssh-port'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t.sshHelp, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
      if (draft.isTotp == false) ...[
        _field(draft.username, t.vaultUsername, 'entry-username'),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: draft.password,
          builder: (context, value, _) => _field(
            draft.password,
            t.vaultPasswordLength(length: value.text.characters.length),
            'entry-password',
            secret: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('entry-password-options'),
                  tooltip: t.vaultPasswordOptions,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  padding: const EdgeInsets.all(8),
                  onPressed: busy ? null : onPasswordOptions,
                  icon: const Icon(Icons.tune_rounded, size: 19),
                ),
                IconButton(
                  key: const Key('generate-entry-password'),
                  tooltip: t.regenerate,
                  onPressed: busy ? null : onGenerate,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
        _field(draft.notes, t.vaultNotes, 'entry-notes', lines: 3),
      ],
      if (draft.isTotp) ...[
        _field(draft.totp, t.totpSecret, 'entry-totp', secret: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t.totpSetupHelp, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
      Row(
        children: [
          TextButton(
            onPressed: busy ? null : onCancel,
            child: Text(t.cancel),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: t.vaultDeleteEntry,
              key: const Key('delete-editing-entry'),
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          const Spacer(),
          FilledButton(
            key: const Key('save-entry'),
            onPressed: busy ? null : onSave,
            child: Text(busy ? t.saving : t.save),
          ),
        ],
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool secret = false,
    int lines = 1,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    VoidCallback? onSubmit,
  }) => _VaultField(
    controller: controller,
    label: label,
    fieldKey: key,
    busy: busy,
    secret: secret,
    lines: lines,
    suffixIcon: suffixIcon,
    textInputAction: textInputAction,
    onSubmit: onSubmit,
  );
}
