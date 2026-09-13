import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';
import 'package:skysecret/core/settings/vault_preferences.dart';
import 'package:skysecret/core/storage/local_file.dart';

class GrowingHandle extends Fake implements RandomAccessFile {
  int requested = 0;
  bool closed = false;

  @override
  Future<int> length() async => 1;

  @override
  Future<Uint8List> read(int bytes) async {
    requested = bytes;
    return Uint8List(bytes);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class GrowingFile extends Fake implements File {
  @override
  final String path;
  final GrowingHandle handle;

  GrowingFile(this.path, this.handle);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async => handle;
}

void main() {
  test('bounded reads reject large files, directories and growth after size inspection', () async {
    final directory = await Directory.systemTemp.createTemp('sky-file-audit-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/data');
    expect(await readBoundedFile(file, maxBytes: 16), isNull);
    await file.writeAsBytes(Uint8List(17));
    await expectLater(readBoundedFile(file, maxBytes: 16), throwsA(isA<FileSystemException>()));
    await expectLater(readBoundedFile(File(directory.path), maxBytes: 16), throwsA(isA<FileSystemException>()));
    final handle = GrowingHandle();
    await expectLater(
      readBoundedFile(GrowingFile(file.path, handle), maxBytes: 16),
      throwsA(isA<FileSystemException>()),
    );
    expect(handle.requested, 17);
    expect(handle.closed, isTrue);
  });

  test('settings reject excessive input without changing in-memory security preferences', () async {
    final directory = await Directory.systemTemp.createTemp('sky-settings-limit-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.json');
    await file.writeAsBytes(Uint8List(16 * 1024 + 1));
    final preferences = VaultPreferences(file: file);
    await expectLater(preferences.loadAutoLock(), throwsA(isA<FileSystemException>()));
    expect(preferences.captureAllowed, isFalse);
    expect(preferences.lockWhenHidden, isTrue);
    await expectLater(ShortcutStore(file: file).load(), throwsA(isA<FileSystemException>()));
    expect(await file.length(), 16 * 1024 + 1);
  });

  test('settings save never overwrites a pre-existing predictable temporary file', () async {
    final directory = await Directory.systemTemp.createTemp('sky-settings-temp-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.json');
    final unrelated = File('${file.path}.tmp');
    await unrelated.writeAsString('synthetic unrelated file');
    await VaultPreferences(file: file).save(true, lockWhenHidden: true);
    expect(await unrelated.readAsString(), 'synthetic unrelated file');
    expect(await VaultPreferences(file: file).loadAutoLock(), isTrue);
    await ShortcutStore(file: file).save(defaultShortcut());
    expect(await unrelated.readAsString(), 'synthetic unrelated file');
    expect(await ShortcutStore(file: file).load(), isNotNull);
    expect((await directory.list().toList()).whereType<Directory>(), isEmpty);
  });
}
