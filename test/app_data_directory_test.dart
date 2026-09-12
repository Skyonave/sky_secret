import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/storage/app_data_directory.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('skysecret-paths-');
  });
  tearDown(() async => root.delete(recursive: true));

  test('fresh install selects SkySecret without creating data', () {
    expect(
      appDataDirectory(root: root.path).path,
      '${root.path}${Platform.pathSeparator}SkySecret',
    );
    expect(root.listSync(), isEmpty);
  });

  test('upgrade retains legacy data even if a new directory exists', () async {
    final legacy = await Directory(
      '${root.path}${Platform.pathSeparator}SecretManager',
    ).create();
    final vault = await File('${legacy.path}/vault.smv')
        .writeAsBytes([1, 2, 3]);
    await Directory('${root.path}/SkySecret').create();
    expect(appDataDirectory(root: root.path).path, legacy.path);
    expect(await vault.readAsBytes(), [1, 2, 3]);
  });

  test(
    'invalid legacy path fails instead of selecting an empty store',
    () async {
      await File('${root.path}/SecretManager').writeAsString('placeholder');
      expect(
        () => appDataDirectory(root: root.path),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('invalid current path fails', () async {
    await File('${root.path}/SkySecret').writeAsString('placeholder');
    expect(
      () => appDataDirectory(root: root.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('missing app data root fails', () {
    expect(
      () => appDataDirectory(root: ''),
      throwsA(isA<FileSystemException>()),
    );
  });
}
