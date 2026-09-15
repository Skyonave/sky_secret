import 'dart:io';

String fileExtension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  final extension = name.substring(dot + 1);
  if (RegExp(r'[<>:"/\\|?*;\s]').hasMatch(extension)) return '';
  return extension;
}

Future<String?> resolveFileSaveTarget({
  required String selectedPath,
  required String suggestedName,
  required Future<bool> Function(String path) confirmReplacement,
  bool requireExtension = false,
  Future<bool> Function(String path)? exists,
}) async {
  final extension = fileExtension(suggestedName);
  if (extension.isEmpty) return selectedPath;
  final selectedExtension = fileExtension(selectedPath);
  if (selectedExtension.toLowerCase() == extension.toLowerCase()) return selectedPath;
  if (selectedExtension.isNotEmpty && requireExtension == false) return selectedPath;
  final path = '${selectedPath.replaceFirst(RegExp(r'[. ]+$'), '')}.$extension';
  final occupied = exists == null
      ? await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound
      : await exists(path);
  if (occupied && await confirmReplacement(path) == false) return null;
  return path;
}
