import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop/search_session.dart';
import '../../i18n/translations.g.dart';
import '../shared/app_theme.dart';
import '../shared/input/sensitive_text_editing.dart';

part '_search_suggestion.dart';

class VaultSearchWindow extends StatefulWidget {
  final VaultSearchSession session;
  final Future<bool> Function(String) copy;

  const VaultSearchWindow({super.key, required this.session, required this.copy});

  @override
  State<VaultSearchWindow> createState() => _VaultSearchWindowState();
}

class _VaultSearchWindowState extends State<VaultSearchWindow> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<Map<String, Object>> _results = [];
  int _selected = 0;
  double _rowHeight = 80;
  bool _selecting = false;

  void _activity() {
    if (widget.session.valid) widget.session.activity();
  }

  Future<bool> _copy(String text) async => widget.session.valid && await widget.copy(text);

  void _changed(String query) {
    setState(() {
      _results = widget.session.search(query);
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int offset) {
    if (_results.isEmpty || _selecting) return;
    _activity();
    setState(() => _selected = (_selected + offset).clamp(0, _results.length - 1));
    if (_scroll.hasClients) {
      final top = _selected * _rowHeight;
      final bottom = top + _rowHeight;
      final position = _scroll.position;
      if (top < position.pixels) {
        _scroll.jumpTo(top.clamp(0, position.maxScrollExtent));
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo((bottom - position.viewportDimension).clamp(0, position.maxScrollExtent));
      }
    }
  }

  Future<void> _choose(int index) async {
    if (_selecting || index < 0 || index >= _results.length) return;
    final id = _results[index]['id'] as String;
    if (!widget.session.accepts(id)) return;
    _selecting = true;
    Navigator.of(context).pop(id);
  }

  Future<void> _dismiss() async => Navigator.of(context).pop();

  @override
  void dispose() {
    _query.clear();
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    _results = [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_dismiss()),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
    },
    child: Listener(
      onPointerDown: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: Scaffold(key: const Key('vault-search-page'), body: _content(context)),
    ),
  );

  Widget _content(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight = (scale.scale(16) + scale.scale(12) + 40).clamp(80, double.infinity);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => windowManager.startDragging(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Text(t.browserSearch, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              IconButton(
                tooltip: t.browserCloseSearch,
                padding: const EdgeInsets.all(10),
                onPressed: () => unawaited(_dismiss()),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SensitiveTextEditing(
            controller: _query,
            copy: _copy,
            enabled: _selecting == false,
            builder: (context, menuBuilder) => TextField(
              controller: _query,
              focusNode: _focus,
              autofocus: true,
              key: const Key('vault-search-query'),
              contextMenuBuilder: menuBuilder,
              enableIMEPersonalizedLearning: false,
              autocorrect: false,
              enableSuggestions: false,
              enabled: _selecting == false,
              maxLength: 256,
              onChanged: _changed,
              onSubmitted: (_) => unawaited(_choose(_selected)),
              decoration: InputDecoration(
                hintText: t.browserSearchHint,
                counterText: '',
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(_query.text.trim().isEmpty ? t.searchStartTyping : t.browserNoResults))
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowHeight,
                    itemCount: _results.length,
                    itemBuilder: (context, index) => _SearchSuggestion(
                      result: _results[index],
                      selected: index == _selected,
                      onSelect: () => unawaited(_choose(index)),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _results.length == 50 ? t.searchRefine : t.searchKeyboardHelp,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
