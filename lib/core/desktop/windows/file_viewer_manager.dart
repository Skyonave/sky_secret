import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../files/text_document.dart';
import '../../os/windows/window_privacy.dart';

class FileViewerManager {
  final bool Function(int) _registerWindow;
  final _windows = <_Viewer>[];

  FileViewerManager({this._registerWindow = WindowPrivacy.registerWindow});

  bool get hasOpenViewers => _windows.any((viewer) => viewer.active);

  Future<void> open({
    required String id,
    required String name,
    required String text,
    required String encoding,
    required String locale,
    required bool Function() isValid,
    required void Function() activity,
    required Future<bool> Function(String) save,
    required Future<bool> Function(String) copy,
    required Future<void> Function() clearClipboard,
  }) async {
    for (final viewer in _windows.where((v) => v.id == id && v.active)) {
      try {
        await viewer.controller?.show();
        return;
      } catch (_) {
        viewer.active = false;
      }
    }
    final token = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final viewer = _Viewer(id, WindowMethodChannel('skysecret/editor/$token'));
    _windows.add(viewer);
    viewer.initialText = text;
    await viewer.channel.setMethodCallHandler((call) async {
      if (call.method == 'closed') {
        viewer.active = false;
        viewer.initialText = '';
        _windows.remove(viewer);
        unawaited(viewer.channel.setMethodCallHandler(null));
        return true;
      }
      if (!viewer.active || !isValid()) return null;
      if (call.method == 'privacy') {
        final id = call.arguments;
        viewer.private = id is int && _registerWindow(id);
        return viewer.private;
      }
      if (viewer.private == false) return null;
      switch (call.method) {
        case 'read':
          final data = {
            'name': name,
            'text': viewer.initialText,
            'encoding': encoding,
          };
          viewer.initialText = '';
          return data;
        case 'alive':
          return true;
        case 'activity':
          activity();
          return true;
        case 'save':
          if (call.arguments is! String || (call.arguments as String).length > TextDocument.maxBytes) return false;
          activity();
          return save(call.arguments as String);
        case 'copy':
          if (call.arguments is! String || (call.arguments as String).length > TextDocument.maxBytes) return false;
          final copied = await copy(call.arguments as String);
          if (!viewer.active || !isValid()) {
            await clearClipboard();
            return false;
          }
          return copied;
      }
      return null;
    });
    try {
      viewer.controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'file-editor',
            'channel': viewer.channel.name,
            'locale': locale,
          }),
        ),
      );
      if (!viewer.active || !isValid()) await _close(viewer);
    } catch (_) {
      viewer.active = false;
      viewer.initialText = '';
      _windows.remove(viewer);
      await viewer.channel.setMethodCallHandler(null);
      rethrow;
    }
  }

  void closeAll() {
    for (final viewer in List<_Viewer>.of(_windows)) {
      viewer.active = false;
      unawaited(_close(viewer));
    }
    _windows.clear();
  }

  void close(String id) {
    for (final viewer in _windows.where((v) => v.id == id).toList()) {
      viewer.active = false;
      unawaited(_close(viewer));
      _windows.remove(viewer);
    }
  }

  Future<void> _close(_Viewer viewer) async {
    viewer.initialText = '';
    try {
      await viewer.controller?.hide();
    } catch (_) {}
    try {
      await viewer.channel.invokeMethod('lock').timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await viewer.channel.setMethodCallHandler(null);
    } catch (_) {}
  }
}

class _Viewer {
  final String id;
  final WindowMethodChannel channel;
  bool active = true;
  bool private = false;
  String initialText = '';
  WindowController? controller;

  _Viewer(this.id, this.channel);
}
