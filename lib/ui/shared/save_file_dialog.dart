import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/files/file_save_target.dart';
import '../../i18n/translations.g.dart';

Future<File?> selectSaveFile({
  required BuildContext context,
  required String suggestedName,
  required bool Function() allowed,
  bool requireExtension = false,
}) async {
  final extension = fileExtension(suggestedName);
  final destination = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      if (extension.isNotEmpty) XTypeGroup(label: '*.$extension', extensions: [extension]),
    ],
  );
  if (destination == null || !context.mounted || !allowed()) return null;
  final path = await resolveFileSaveTarget(
    selectedPath: destination.path,
    suggestedName: suggestedName,
    requireExtension: requireExtension,
    confirmReplacement: (path) async {
      if (!context.mounted || !allowed()) return false;
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t.fileReplaceTitle),
              content: Text(t.fileReplaceBody(path: path)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.fileReplace)),
              ],
            ),
          ) ==
          true;
    },
  );
  if (path == null || !context.mounted || !allowed()) return null;
  return File(path);
}
