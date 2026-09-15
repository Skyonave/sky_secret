import 'dart:math' as math;

import 'package:flutter/material.dart';

Offset desktopTooltipPosition({
  required Offset pointer,
  required Size tooltip,
  required Size overlay,
}) {
  final maxX = math.max(8.0, overlay.width - tooltip.width - 8);
  final maxY = math.max(8.0, overlay.height - tooltip.height - 8);
  var y = pointer.dy + 20;
  if (y > maxY) y = pointer.dy - tooltip.height - 12;
  return Offset((pointer.dx + 12).clamp(8.0, maxX), y.clamp(8.0, maxY));
}

class DesktopTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const DesktopTooltip({super.key, required this.message, required this.child});

  static final _active = <_DesktopTooltipState>{};

  static void dismissAll() {
    Tooltip.dismissAllToolTips();
    for (final state in _active.toList()) {
      state.dismiss();
    }
  }

  @override
  State<DesktopTooltip> createState() => _DesktopTooltipState();
}

class _DesktopTooltipState extends State<DesktopTooltip> {
  final _childKey = GlobalKey();
  Offset? _pointer;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    DesktopTooltip._active.add(this);
  }

  @override
  void dispose() {
    DesktopTooltip._active.remove(this);
    super.dispose();
  }

  void dismiss() {
    setState(() {
      _pointer = null;
      _enabled = false;
    });
  }

  void _hover(Offset position) {
    _pointer = position;
    if (_enabled == false) setState(() => _enabled = true);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) => _hover(event.position),
    onHover: (event) => _hover(event.position),
    child: TooltipVisibility(
      visible: _enabled,
      child: Tooltip(
        message: widget.message,
        triggerMode: TooltipTriggerMode.manual,
        enableFeedback: false,
        positionDelegate: (position) {
          final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          return desktopTooltipPosition(
            pointer: _pointer == null ? position.target : overlay.globalToLocal(_pointer!),
            tooltip: position.tooltipSize,
            overlay: position.overlaySize,
          );
        },
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    ),
  );
}

class DesktopIconButton extends IconButton {
  const DesktopIconButton({
    super.key,
    required super.icon,
    required super.onPressed,
    super.tooltip,
    super.padding,
    super.constraints,
    super.visualDensity,
    super.style,
    super.iconSize,
    super.color,
  });

  @override
  Widget build(BuildContext context) {
    final button = super.build(context);
    if (tooltip == null) return button;
    return DesktopTooltip(
      message: tooltip!,
      child: TooltipVisibility(visible: false, child: button),
    );
  }
}
