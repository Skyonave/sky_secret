import 'dart:convert';
import 'dart:io';

import '../crypto/generator_options.dart';
import '../storage/app_data_directory.dart';
import '../storage/local_file.dart';

class GeneratorPreferences {
  final File? file;
  Future<GeneratorOptions>? _loading;
  Future<void> _writes = Future.value();

  GeneratorPreferences({this.file});

  factory GeneratorPreferences.local() => GeneratorPreferences(
    file: File('${appDataDirectory().path}${Platform.pathSeparator}generator_preferences.json'),
  );

  Future<GeneratorOptions> load() async {
    await _writes;
    return _loading ??= _read();
  }

  Future<GeneratorOptions> _read() async {
    if (file == null) return const GeneratorOptions();
    final bytes = await readBoundedFile(file!, maxBytes: 4096);
    return bytes == null ? const GeneratorOptions() : GeneratorOptions.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> save(GeneratorOptions options) {
    if (!options.valid) return Future.error(ArgumentError('Invalid generator options'));
    final write = _writes.then((_) async {
      if (file != null) await writeAtomicFile(file!, utf8.encode(jsonEncode(options.toJson())));
      _loading = Future.value(options);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return write;
  }
}
