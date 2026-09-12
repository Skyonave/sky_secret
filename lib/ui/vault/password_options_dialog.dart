import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';

typedef PasswordOptions = ({int length, bool symbols});

class PasswordOptionsDialog extends StatefulWidget {
  final PasswordOptions options;

  const PasswordOptionsDialog({super.key, required this.options});

  @override
  State<PasswordOptionsDialog> createState() => _PasswordOptionsDialogState();
}

class _PasswordOptionsDialogState extends State<PasswordOptionsDialog> {
  late int _length = widget.options.length;
  late bool _symbols = widget.options.symbols;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.vaultPasswordOptions),
    scrollable: true,
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.length)),
              Text('$_length', key: const Key('entry-generation-length')),
            ],
          ),
          Slider(
            key: const Key('entry-length-slider'),
            value: _length.toDouble(),
            min: 12,
            max: 64,
            divisions: 52,
            label: '$_length',
            onChanged: (value) => setState(() => _length = value.round()),
          ),
          SwitchListTile(
            key: const Key('entry-symbols-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(t.symbols),
            value: _symbols,
            onChanged: (value) => setState(() => _symbols = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t.cancel),
      ),
      FilledButton(
        key: const Key('apply-password-options'),
        onPressed: () => Navigator.pop(context, (length: _length, symbols: _symbols)),
        child: Text(t.vaultGeneratePassword),
      ),
    ],
  );
}
