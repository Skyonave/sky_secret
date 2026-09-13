import 'dart:io';

Directory appDataDirectory({String? root}) {
  final base = root ?? Platform.environment['LOCALAPPDATA'];
  if (base == null || base.isEmpty) {
    throw const FileSystemException('Local application data is unavailable');
  }
  final legacy = Directory('$base${Platform.pathSeparator}SecretManager');
  final legacyType = FileSystemEntity.typeSync(legacy.path, followLinks: false);
  if (legacyType == FileSystemEntityType.directory) return legacy;
  if (legacyType != FileSystemEntityType.notFound) {
    throw const FileSystemException('Legacy application directory is invalid');
  }
  final current = Directory('$base${Platform.pathSeparator}SkySecret');
  final currentType = FileSystemEntity.typeSync(
    current.path,
    followLinks: false,
  );
  if (currentType != FileSystemEntityType.notFound && currentType != FileSystemEntityType.directory) {
    throw const FileSystemException('Application directory is invalid');
  }
  return current;
}
