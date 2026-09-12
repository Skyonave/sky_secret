import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class NativeFileDropTarget extends StatefulWidget {
  final Widget child;
  final bool enable;
  final ValueChanged<bool> onHover;
  final ValueChanged<List<String>> onFiles;
  final VoidCallback onRejected;
  final VoidCallback onUnavailable;
  final ValueChanged<Offset>? onPosition;

  const NativeFileDropTarget({
    super.key,
    required this.child,
    required this.enable,
    required this.onHover,
    required this.onFiles,
    required this.onRejected,
    required this.onUnavailable,
    this.onPosition,
  });

  @override
  State<NativeFileDropTarget> createState() => _NativeFileDropTargetState();
}

class _NativeFileDropTargetState extends State<NativeFileDropTarget> {
  static const channel = MethodChannel('skysecret/file_drop');

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (!mounted || !widget.enable) return false;
      switch (call.method) {
        case 'position':
          final point = (call.arguments as List).cast<num>();
          widget.onPosition?.call(Offset(point[0].toDouble(), point[1].toDouble()));
        case 'entered':
          widget.onHover(true);
        case 'exited':
          widget.onHover(false);
        case 'rejected':
          widget.onHover(false);
          widget.onRejected();
        case 'files':
          final paths = (call.arguments as List).cast<String>();
          if (paths.isNotEmpty) widget.onFiles(paths);
          widget.onHover(false);
      }
      return true;
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      if (await channel.invokeMethod<bool>('ready') == false && mounted) {
        widget.onUnavailable();
      }
    } on MissingPluginException catch (_) {
    } catch (_) {
      if (mounted) widget.onUnavailable();
    }
  }

  @override
  void didUpdateWidget(NativeFileDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enable && oldWidget.enable) widget.onHover(false);
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
