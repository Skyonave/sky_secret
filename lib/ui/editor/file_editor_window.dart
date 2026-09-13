import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop/windows/file_editor_channel.dart';
import '../../core/desktop/clipboard/sensitive_clipboard_boundary.dart';
import '../../core/files/text_document.dart';
import '../../i18n/translations.g.dart';
import '../shared/input/sensitive_text_editing.dart';

Future<bool> runFileEditorIfNeeded({SensitiveClipboardBoundary? clipboardBoundary}) async {
  final controller = await WindowController.fromCurrentEngine();
  if (controller.arguments.isEmpty) return false;
  final args = jsonDecode(controller.arguments);
  if (args is! Map || args['type'] != 'file-editor') return false;
  await LocaleSettings.setLocale(
    args['locale'] == 'en' ? AppLocale.en : AppLocale.ru,
  );
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(860, 640),
      minimumSize: Size(480, 360),
      center: true,
      backgroundColor: const Color(0xFF0B131B),
      title: t.appName,
    ),
  );
  runApp(
    TranslationProvider(
      child: FileEditorWindow(
        clipboardBoundary: clipboardBoundary,
        channel: WindowMethodChannel(args['channel'] as String),
      ),
    ),
  );
  return true;
}

class FileEditorWindow extends StatefulWidget {
  final WindowMethodChannel channel;
  final SensitiveClipboardBoundary? clipboardBoundary;

  const FileEditorWindow({
    super.key,
    required this.channel,
    this.clipboardBoundary,
  });

  @override
  State<FileEditorWindow> createState() => _FileEditorWindowState();
}

class _FileEditorWindowState extends State<FileEditorWindow> with WindowListener {
  final _text = TextEditingController();
  final _navigator = GlobalKey<NavigatorState>();
  String _saved = '';
  String _name = '';
  String _encoding = '';
  String? _error;
  bool _loaded = false;
  bool _saving = false;
  bool _closing = false;
  bool _askingClose = false;
  bool _pinging = false;
  Timer? _timer;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _dirty => _text.text != _saved;

  @override
  void initState() {
    super.initState();
    widget.clipboardBoundary?.attach(_copyText);
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_keyActivity);
    _text.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted && !_closing) setState(() {});
  }

  bool _keyActivity(KeyEvent event) {
    _activity();
    return false;
  }

  void _activity() {
    if (_closing || DateTime.now().difference(_lastActivity).inMilliseconds < 500) {
      return;
    }
    _lastActivity = DateTime.now();
    unawaited(widget.channel.invokeMethod('activity').catchError((_) => null));
  }

  Future<void> _load() async {
    try {
      final privacyApplied = await connectFileEditor(
        channel: widget.channel,
        getWindowId: windowManager.getId,
        onLock: _destroy,
      );
      if (_closing || !mounted) return;
      if (!privacyApplied) {
        await _destroy();
        return;
      }
      final data = await widget.channel.invokeMethod<Map>('read');
      if (data == null || _closing || !mounted) {
        await _destroy();
        return;
      }
      _name = data['name'] as String;
      _saved = data['text'] as String;
      _encoding = data['encoding'] as String;
      _text.text = _saved;
      if (await widget.channel.invokeMethod<bool>('alive') != true || _closing) {
        await _destroy();
        return;
      }
      if (!mounted) return;
      setState(() => _loaded = true);
      await windowManager.setTitle('$_name — ${t.appName}');
      if (_closing) return;
      await windowManager.show();
      await windowManager.focus();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _ping());
    } catch (_) {
      await _destroy();
    }
  }

  Future<void> _ping() async {
    if (_pinging || _closing) return;
    _pinging = true;
    try {
      if (await widget.channel.invokeMethod<bool>('alive').timeout(const Duration(seconds: 3)) != true) {
        await _destroy();
      }
    } catch (_) {
      await _destroy();
    } finally {
      _pinging = false;
    }
  }

  Future<bool> _save() async {
    if (_saving || !_loaded || _closing) return false;
    if (!_dirty) return true;
    final snapshot = _text.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final success = await widget.channel.invokeMethod<bool>('save', snapshot);
      if (!mounted || _closing) return false;
      if (success == true) {
        setState(() => _saved = snapshot);
        return true;
      }
      setState(() => _error = t.fileEditorSaveFailed);
    } catch (_) {
      if (mounted && !_closing) setState(() => _error = t.fileEditorSaveFailed);
    } finally {
      if (mounted && !_closing) setState(() => _saving = false);
    }
    return false;
  }

  Future<bool> _copyText(String text) async {
    if (_closing || _saving || _loaded == false) return false;
    try {
      return await widget.channel.invokeMethod<bool>('copy', text) ?? false;
    } catch (_) {
      if (mounted && _closing == false) setState(() => _error = t.clipboardBusy);
      return false;
    }
  }

  void _indent() {
    if (_saving || _closing) return;
    final value = _text.value;
    if (!value.selection.isValid) return;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        '  ',
      ),
      selection: TextSelection.collapsed(offset: value.selection.start + 2),
    );
  }

  @override
  void onWindowClose() => unawaited(_requestClose());

  Future<void> _requestClose() async {
    if (_closing || _askingClose || _saving) return;
    if (!_dirty) {
      await _destroy();
      return;
    }
    _askingClose = true;
    final choice = await showDialog<String>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: Text(t.fileEditorUnsaved),
        content: Text(t.fileEditorCloseHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(t.fileEditorDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(t.save),
          ),
        ],
      ),
    );
    _askingClose = false;
    if (_closing) return;
    if (choice == 'discard' || (choice == 'save' && await _save())) {
      await _destroy();
    }
  }

  Future<void> _destroy() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _text.clear();
    _saved = '';
    _name = '';
    _error = null;
    if (mounted) setState(() => _loaded = false);
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await widget.channel.invokeMethod('closed');
    } catch (_) {}
    try {
      await widget.channel.setMethodCallHandler(null);
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void dispose() {
    widget.clipboardBoundary?.detach(_copyText);
    _timer?.cancel();
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_keyActivity);
    _text.removeListener(_changed);
    _text.clear();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xFF0B131B),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6CDEFF),
        onPrimary: Color(0xFF062633),
        surface: Color(0xFF13212D),
      ),
    ),
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.tab): _indent,
        const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_requestClose()),
      },
      child: Listener(
        onPointerDown: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: Scaffold(
          body: !_loaded
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      color: const Color(0xFF13212D),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.description_outlined,
                            color: Color(0xFF6CDEFF),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17),
                                ),
                                Text(
                                  _dirty ? t.fileEditorModified : t.fileEditorStored,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8FA7B6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            key: const Key('file-editor-save'),
                            onPressed: _saving || !_dirty ? null : _save,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: Text(_saving ? t.saving : t.save),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SensitiveTextEditing(
                          controller: _text,
                          enabled: true,
                          readOnly: _saving,
                          obscureText: false,
                          copy: _copyText,
                          builder: (context, menuBuilder) => TextField(
                            enableIMEPersonalizedLearning: false,
                            key: const Key('file-editor-text'),
                            controller: _text,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            maxLength: TextDocument.maxBytes,
                            readOnly: _saving,
                            autofocus: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 14,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              counterText: '',
                              isCollapsed: true,
                            ),
                            contextMenuBuilder: menuBuilder,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            _encoding,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8FA7B6),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            t.fileEditorShortcut,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8FA7B6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
