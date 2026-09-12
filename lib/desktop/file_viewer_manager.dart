import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'window_privacy.dart';

class FileViewerManager {
  final _windows = <_Viewer>[];

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
    required Future<void> Function(String) copy,
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
    var initialText = text;
    await viewer.channel.setMethodCallHandler((call) async {
      if (!viewer.active || !isValid()) return null;
      switch (call.method) {
        case 'privacy':
          final id = call.arguments;
          return id is int && WindowPrivacy.registerWindow(id);
        case 'read':
          final data = {
            'name': name,
            'text': initialText,
            'encoding': encoding,
          };
          initialText = '';
          return data;
        case 'alive':
          return true;
        case 'activity':
          activity();
          return true;
        case 'save':
          if (call.arguments is! String) return false;
          activity();
          return save(call.arguments as String);
        case 'copy':
          if (call.arguments is! String) return false;
          await copy(call.arguments as String);
          if (!viewer.active || !isValid()) await clearClipboard();
          return true;
        case 'closed':
          viewer.active = false;
          initialText = '';
          _windows.remove(viewer);
          unawaited(viewer.channel.setMethodCallHandler(null));
          return true;
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
    try {
      await viewer.controller?.hide();
    } catch (_) {}
    try {
      await viewer.channel.invokeMethod('lock');
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
  WindowController? controller;

  _Viewer(this.id, this.channel);
}
