import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/generator_options.dart';
import 'package:skysecret/core/settings/generator_preferences.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sky-generator-preferences-');
    file = File('${directory.path}/preferences.json');
  });
  tearDown(() => directory.delete(recursive: true));

  test('defaults and all settings survive restart, only settings are stored', () async {
    final preferences = GeneratorPreferences(file: file);
    expect((await preferences.load()).toJson(), const GeneratorOptions().toJson());
    const options = GeneratorOptions(
      mode: GeneratorMode.passphrase,
      length: 64,
      lowercase: false,
      uppercase: false,
      digits: true,
      symbols: false,
      excludeSimilar: true,
      wordCount: 10,
      separator: ' ',
    );
    await preferences.save(options);
    expect((await GeneratorPreferences(file: file).load()).toJson(), options.toJson());
    expect(jsonDecode(await file.readAsString()), options.toJson());
    expect(await directory.list().length, 1);
  });

  test('immediate reopen waits for queued changes and the last change wins', () async {
    final preferences = GeneratorPreferences(file: file);
    await preferences.load();
    final writes = [for (var length = 12; length <= 64; length++) preferences.save(GeneratorOptions(length: length))];
    expect((await preferences.load()).length, 64);
    await Future.wait(writes);
    expect((await GeneratorPreferences(file: file).load()).length, 64);
  });

  test('failed writes preserve previous settings and do not poison the write queue', () async {
    final preferences = GeneratorPreferences(file: file);
    await preferences.save(const GeneratorOptions(length: 30));
    await file.rename('${file.path}.saved');
    await Directory(file.path).create();
    await expectLater(preferences.save(const GeneratorOptions(length: 40)), throwsA(isA<FileSystemException>()));
    expect((await preferences.load()).length, 30);
    await Directory(file.path).delete();
    await preferences.save(const GeneratorOptions(length: 50));
    expect((await GeneratorPreferences(file: file).load()).length, 50);
  });

  test('corrupt settings require an explicit valid save to replace them', () async {
    await file.writeAsString('{broken');
    final preferences = GeneratorPreferences(file: file);
    await expectLater(preferences.load(), throwsFormatException);
    expect(await file.readAsString(), '{broken');
    await preferences.save(const GeneratorOptions(length: 32));
    expect((await preferences.load()).length, 32);
    await expectLater(preferences.save(const GeneratorOptions(length: 2)), throwsArgumentError);
    expect((await GeneratorPreferences(file: file).load()).length, 32);
  });

  test('oversized preferences are rejected', () async {
    await file.writeAsString(' ' * 4097);
    await expectLater(GeneratorPreferences(file: file).load(), throwsA(isA<FileSystemException>()));
  });
}
