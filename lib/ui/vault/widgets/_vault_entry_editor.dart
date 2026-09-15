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
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        if (busy == false) onSave();
      },
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: locationSelector,
        ),
        _field(draft.title, t.vaultEntryTitle, 'entry-title'),
        if (isSsh) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _field(draft.sshHost, t.sshHost, 'ssh-host')),
              const SizedBox(width: 10),
              Expanded(child: _field(draft.sshPort, t.sshPort, 'ssh-port')),
            ],
          ),
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('entry-password-options'),
                  onPressed: busy ? null : onPasswordOptions,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(t.generatorOpen),
                ),
                OutlinedButton.icon(
                  key: const Key('generate-entry-password'),
                  onPressed: busy ? null : onGenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(t.generatorAgain),
                ),
              ],
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
              DesktopIconButton(
                tooltip: t.vaultDeleteEntry,
                key: const Key('delete-editing-entry'),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            const Spacer(),
            DesktopTooltip(
              message: '${t.save} · Ctrl+S',
              child: FilledButton(
                key: const Key('save-entry'),
                onPressed: busy ? null : onSave,
                child: Text(busy ? t.saving : t.save),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool secret = false,
    int lines = 1,

    TextInputAction? textInputAction,
    VoidCallback? onSubmit,
  }) => _VaultField(
    controller: controller,
    label: label,
    fieldKey: key,
    busy: busy,
    secret: secret,
    lines: lines,

    textInputAction: textInputAction,
    onSubmit: onSubmit,
  );
}
