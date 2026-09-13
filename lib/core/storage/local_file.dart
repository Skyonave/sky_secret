import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readBoundedFile(File file, {required int maxBytes}) async {
  if (maxBytes < 1) throw ArgumentError.value(maxBytes, 'maxBytes');
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  if (type != FileSystemEntityType.file) throw const FileSystemException('Expected a regular file');
  final handle = await file.open();
  try {
    if (await handle.length() > maxBytes) throw const FileSystemException('File exceeds size limit');
    final bytes = await handle.read(maxBytes + 1);
    if (bytes.length > maxBytes) throw const FileSystemException('File exceeds size limit');
    return bytes;
  } finally {
    await handle.close();
  }
}

Future<void> writeAtomicFile(File file, List<int> bytes) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
    throw const FileSystemException('Expected a regular file');
  }
  await file.parent.create(recursive: true);
  final staging = await file.parent.createTemp('settings-staging-');
  final pending = File('${staging.path}${Platform.pathSeparator}data');
  try {
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(file.path);
  } finally {
    try {
      if (await pending.exists()) await pending.delete();
      await staging.delete();
    } on FileSystemException catch (_) {}
  }
}
