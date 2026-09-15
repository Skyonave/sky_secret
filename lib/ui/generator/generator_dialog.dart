import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/generator_options.dart';
import '../../i18n/translations.g.dart';
import '../shared/app_theme.dart';
import '../shared/desktop_menu.dart';
import '../shared/desktop_option.dart';
import '../shared/desktop_tooltip.dart';
import '../shared/input/sensitive_text_editing.dart';
import 'generator_service.dart';

Future<String?> showGenerator({
  required BuildContext context,
  required GeneratorService service,
  required Future<bool> Function(String) copy,
  required String actionLabel,
  bool canApply = true,
}) {
  DesktopTooltip.dismissAll();
  return showDialog<String>(
    context: context,
    routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
    animationStyle: AnimationStyle.noAnimation,
    builder: (_) => GeneratorDialog(service: service, copy: copy, actionLabel: actionLabel, canApply: canApply),
  );
}

class GeneratorDialog extends StatefulWidget {
  final GeneratorService service;
  final Future<bool> Function(String) copy;
  final String actionLabel;
  final bool canApply;

  const GeneratorDialog({
    super.key,
    required this.service,
    required this.copy,
    required this.actionLabel,
    required this.canApply,
  });

  @override
  State<GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<GeneratorDialog> {
  GeneratorOptions _options = const GeneratorOptions();
  final _count = TextEditingController();
  String _value = '';
  String? _error;
  String? _preferencesError;
  bool _loading = true;
  bool _generating = false;
  bool _copying = false;
  bool _copied = false;
  bool _countValid = true;
  int _revision = 0;
  Timer? _copyNotice;

  bool get _phrase => _options.mode == GeneratorMode.passphrase;
  bool get _ready => !_loading && !_generating && _countValid && _options.valid && _value.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _options = await widget.service.preferences.load();
    } catch (_) {
      _preferencesError = t.generatorPreferencesFailed;
    }
    if (!mounted) return;
    _count.text = '${_phrase ? _options.wordCount : _options.length}';
    setState(() => _loading = false);
    await _generate();
  }

  Future<void> _generate() async {
    final revision = ++_revision;
    setState(() {
      _value = '';
      _copied = false;
      _error = null;
      _generating = _countValid && _options.valid;
    });
    if (!_generating) return;
    try {
      final value = await widget.service.generate(_options);
      if (mounted && revision == _revision) setState(() => _value = value);
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = t.generatorFailed);
    } finally {
      if (mounted && revision == _revision) setState(() => _generating = false);
    }
  }

  void _change(GeneratorOptions options) {
    setState(() => _options = options);
    unawaited(_generate());
    if (options.valid && _countValid) unawaited(_save(options));
  }

  Future<void> _save(GeneratorOptions options) async {
    try {
      await widget.service.preferences.save(options);
      if (mounted) setState(() => _preferencesError = null);
    } catch (_) {
      if (mounted) setState(() => _preferencesError = t.generatorPreferencesFailed);
    }
  }

  void _changeMode(GeneratorMode mode) {
    _countValid = true;
    _count.text = '${mode == GeneratorMode.passphrase ? _options.wordCount : _options.length}';
    _change(_options.copyWith(mode: mode));
  }

  Future<void> _copy() async {
    if (!_ready || _copying) return;
    final revision = _revision;
    setState(() => _copying = true);
    try {
      final copied = await widget.copy(_value);
      if (!mounted || revision != _revision) return;
      setState(() {
        _copied = copied;
        _error = copied ? null : t.clipboardBusy;
      });
      _copyNotice?.cancel();
      _copyNotice = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void dispose() {
    _revision++;
    _value = '';
    _copyNotice?.cancel();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    alignment: Alignment.topRight,
    insetPadding: const EdgeInsets.fromLTRB(12, 42, 12, 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.generator, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                DesktopIconButton(
                  tooltip: t.generatorClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _mode(GeneratorMode.password, t.generatorPassword)),
                const SizedBox(width: 6),
                Expanded(child: _mode(GeneratorMode.passphrase, t.generatorPassphrase)),
              ],
            ),
            const SizedBox(height: 12),
            _preview(),
            const SizedBox(height: 12),
            if (!_loading) ...[
              _number(),
              const SizedBox(height: 8),
              if (_phrase) _phraseOptions() else _passwordOptions(),
              if (!_options.valid) _warning(t.generatorChooseGroup),
            ],
            if (_error != null) _warning(_error!),
            if (_preferencesError != null) _warning(_preferencesError!),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('generator-apply'),
              onPressed: _ready && widget.canApply ? () => Navigator.of(context).pop(_value) : null,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(widget.actionLabel),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _mode(GeneratorMode mode, String label) => TextButton(
    onPressed: _loading ? null : () => _changeMode(mode),
    style: TextButton.styleFrom(
      backgroundColor: _options.mode == mode ? AppColors.surface : Colors.transparent,
      side: BorderSide(color: _options.mode == mode ? AppColors.accent : AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    ),
    child: Text(label),
  );

  Widget _preview() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42, maxHeight: 110),
          child: _loading || _generating
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : SingleChildScrollView(
                  child: Text(
                    _value,
                    key: const Key('generated-password'),
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 15, height: 1.45),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_copied) Padding(padding: const EdgeInsets.only(right: 8), child: Text(t.copied)),
            DesktopIconButton(
              key: const Key('generator-regenerate'),
              tooltip: t.regenerate,
              onPressed: !_loading && _countValid && _options.valid ? () => unawaited(_generate()) : null,
              icon: const Icon(Icons.refresh_rounded, size: 17),
            ),
            const SizedBox(width: 4),
            DesktopIconButton(
              key: const Key('generator-copy'),
              tooltip: t.copy,
              onPressed: _ready && !_copying ? () => unawaited(_copy()) : null,
              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_outlined, size: 17),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _number() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(_phrase ? '${t.generatorWords} · 6–10' : '${t.length} · 12–64'),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 120,
        child: SensitiveTextEditing(
          controller: _count,
          builder: (context, menuBuilder) => TextField(
            contextMenuBuilder: menuBuilder,
            enableIMEPersonalizedLearning: false,
            key: const Key('generator-count'),
            controller: _count,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              errorText: _countValid ? null : t.generatorRange,
            ),
            onChanged: (text) {
              final count = int.tryParse(text);
              _countValid = count != null && count >= (_phrase ? 6 : 12) && count <= (_phrase ? 10 : 64);
              _change(
                _countValid
                    ? (_phrase ? _options.copyWith(wordCount: count) : _options.copyWith(length: count))
                    : _options,
              );
            },
          ),
        ),
      ),
    ],
  );

  Widget _passwordOptions() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: DesktopOption(
              title: 'a–z',
              value: _options.lowercase,
              onChanged: (value) => _change(_options.copyWith(lowercase: value)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DesktopOption(
              title: 'A–Z',
              value: _options.uppercase,
              onChanged: (value) => _change(_options.copyWith(uppercase: value)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: DesktopOption(
              title: '0–9',
              value: _options.digits,
              onChanged: (value) => _change(_options.copyWith(digits: value)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DesktopOption(
              title: t.symbols,
              key: const Key('generator-symbols'),
              value: _options.symbols,
              onChanged: (value) => _change(_options.copyWith(symbols: value)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      DesktopTooltip(
        message: t.generatorSimilarHint,
        child: DesktopOption(
          title: t.generatorExcludeSimilar,
          value: _options.excludeSimilar,
          onChanged: (value) => _change(_options.copyWith(excludeSimilar: value)),
        ),
      ),
    ],
  );

  Widget _phraseOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(t.generatorSeparator)),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<String>(
              initialValue: _options.separator,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: ['-', ' ', '_', '.']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value == ' ' ? t.generatorSpace : value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _change(_options.copyWith(separator: value));
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(t.generatorEnglishWords, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ],
  );

  Widget _warning(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: const TextStyle(color: Color(0xFFFFCB8A), fontSize: 11)),
  );
}
