import 'package:flutter/material.dart';

class InsetMenuItem<T> extends PopupMenuEntry<T> {
  final T value;
  final String label;
  final IconData icon;
  final bool selected;
  final bool destructive;

  const InsetMenuItem({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.selected = false,
    this.destructive = false,
  });

  @override
  double get height => 48;

  @override
  bool represents(T? value) => value == this.value;

  @override
  State<InsetMenuItem<T>> createState() => _InsetMenuItemState<T>();
}

class _InsetMenuItemState<T> extends State<InsetMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: Alignment.centerLeft,
          foregroundColor: widget.destructive
              ? colors.error
              : widget.selected
              ? colors.primary
              : colors.onSurface,
          backgroundColor: widget.selected ? colors.primary.withValues(alpha: 0.08) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
        onPressed: () => Navigator.pop(context, widget.value),
        child: Row(
          children: [
            Icon(widget.icon, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, size: 17),
            ],
          ],
        ),
      ),
    );
  }
}
