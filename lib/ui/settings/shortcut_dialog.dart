import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/desktop/desktop_actions.dart';
import '../../core/settings/shortcut_settings.dart';
import '../../i18n/translations.g.dart';

class ShortcutDialog extends StatefulWidget {
  final DesktopActions desktop;

  const ShortcutDialog({super.key, required this.desktop});

  @override
  State<ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<ShortcutDialog> {
  late HotKey _candidate = widget.desktop.shortcut;
  String? _error;
  bool _saving = false;
  final _recorderFocus = FocusNode();
  List<HotKeyModifier> _pressedModifiers = [];
  bool _awaitingKey = false;

  String get _display =>
      _awaitingKey ? [..._pressedModifiers.map((m) => modifierLabels[m]!), '…'].join(' + ') : shortcutLabel(_candidate);

  @override
  void initState() {
    super.initState();
    widget.desktop.setShortcutCapture(true);
  }

  @override
  void dispose() {
    widget.desktop.setShortcutCapture(false);
    _recorderFocus.dispose();
    super.dispose();
  }

  KeyEventResult _record(FocusNode _, KeyEvent event) {
    if (_saving) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape && !supportedModifiers.any((m) => m.isModifierPressed)) {
      if (event is KeyDownEvent) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    final modifiers = supportedModifiers.where((m) => m.isModifierPressed).toList();
    if (HotKeyModifier.values.any(
      (m) => m.physicalKeys.contains(event.physicalKey),
    )) {
      setState(() {
        if (event is KeyDownEvent) _awaitingKey = true;
        _pressedModifiers = modifiers;
        if (modifiers.isEmpty) _awaitingKey = false;
        _error = null;
      });
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final candidate = HotKey(
      key: event.physicalKey,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );
    setState(() {
      _candidate = candidate;
      _awaitingKey = false;
      _error = validShortcut(candidate) ? null : t.unsupportedKey;
    });
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await widget.desktop.updateShortcut(_candidate);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _error = error;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.all(20),
    title: Text(t.shortcutTitle),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.shortcutHelp, style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Focus(
            focusNode: _recorderFocus,
            autofocus: true,
            onKeyEvent: _record,
            onFocusChange: (focused) => setState(() {
              if (!focused) _awaitingKey = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _recorderFocus.requestFocus,
              child: AnimatedContainer(
                key: const Key('shortcut-recorder'),
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(minHeight: 108),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: _recorderFocus.hasFocus ? 2 : 1,
                    color: _recorderFocus.hasFocus
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _display,
                        key: const Key('shortcut-preview'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _recorderFocus.hasFocus
                          ? (_awaitingKey ? t.shortcutPressKey : t.shortcutListening)
                          : t.shortcutClickToRecord,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFCB8A), fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _candidate = defaultShortcut();
                    _awaitingKey = false;
                    _error = null;
                  }),
            child: Text(t.resetShortcut),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: Text(t.cancel),
      ),
      FilledButton(
        onPressed: _saving || _awaitingKey || !validShortcut(_candidate) ? null : _save,
        child: Text(_saving ? t.saving : t.save),
      ),
    ],
  );
}
