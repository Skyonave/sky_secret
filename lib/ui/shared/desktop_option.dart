import 'package:flutter/material.dart';

class DesktopOption extends StatelessWidget {
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const DesktopOption({
    super.key,
    required this.title,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(4),
    clipBehavior: Clip.antiAlias,
    child: CheckboxListTile(
      value: value,
      onChanged: onChanged == null ? null : (value) => onChanged!(value == true),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: description == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(description!, style: const TextStyle(fontSize: 11, height: 1.4)),
            ),
    ),
  );
}
