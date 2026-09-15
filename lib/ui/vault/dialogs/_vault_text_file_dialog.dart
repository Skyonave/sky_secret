part of '../vault_panel.dart';

class _VaultTextFileDialog extends StatefulWidget {
  final Future<String?> Function(String) create;

  const _VaultTextFileDialog({required this.create});

  @override
  State<_VaultTextFileDialog> createState() => _VaultTextFileDialogState();
}

class _VaultTextFileDialogState extends State<_VaultTextFileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${t.vaultTextDefaultName}.txt')
    ..selection = TextSelection(baseOffset: 0, extentOffset: t.vaultTextDefaultName.length);
  bool _saving = false;
  String? _error;

  Future<void> _create() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.create(_name.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _name.clear();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(t.vaultCreateTextFile),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SensitiveTextEditing(
              controller: _name,
              enabled: !_saving,
              readOnly: false,
              obscureText: false,
              builder: (context, menuBuilder) => TextFormField(
                contextMenuBuilder: menuBuilder,
                enableIMEPersonalizedLearning: false,
                key: const Key('text-file-name'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                maxLength: 240,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: t.vaultTextFileName,
                  counterText: '',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.description_outlined, size: 20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
                validator: (value) {
                  try {
                    VaultTextFile.fileName(value ?? '');
                    return null;
                  } on TextFileException {
                    return t.vaultTextNameInvalid;
                  }
                },
                onFieldSubmitted: (_) => _create(),
              ),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        FilledButton.icon(
          key: const Key('create-text-file'),
          onPressed: _saving ? null : _create,
          icon: const Icon(Icons.note_add_outlined, size: 20),
          label: Text(_saving ? t.saving : t.vaultCreateText),
        ),
      ],
    ),
  );
}
