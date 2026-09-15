import 'dart:convert';
import 'dart:io';

import '../storage/local_file.dart';

class VaultTreePreferences {
  final File? file;
  final _collapsed = <String, Set<String>>{};
  Future<void> _saving = Future.value();

  VaultTreePreferences({this.file});

  Set<String> collapsed(String vaultId) => Set.of(_collapsed[vaultId] ?? {});

  Future<void> load() async {
    final source = file;
    if (source == null) return;
    final bytes = await readBoundedFile(source, maxBytes: 1024 * 1024);
    if (bytes == null) return;
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['version'] != 1 || data['vaults'] is! Map) {
      throw const FormatException('Invalid tree preferences');
    }
    final parsed = <String, Set<String>>{};
    for (final entry in (data['vaults'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).any((id) => id is! String || id.length > 256)) {
        throw const FormatException('Invalid tree preferences');
      }
      parsed[entry.key as String] = (entry.value as List).cast<String>().toSet();
    }
    _collapsed
      ..clear()
      ..addAll(parsed);
  }

  Future<void> save(String vaultId, Set<String> collapsed) {
    final next = Set<String>.of(collapsed);
    final operation = _saving.then((_) async {
      final updated = {..._collapsed, vaultId: next};
      final bytes = utf8.encode(
        jsonEncode({'version': 1, 'vaults': updated.map((id, values) => MapEntry(id, values.toList()..sort()))}),
      );
      if (bytes.length > 1024 * 1024) throw const FormatException('Tree preferences too large');
      if (file case final target?) await writeAtomicFile(target, bytes);
      _collapsed[vaultId] = next;
    });
    _saving = operation.catchError((_) {});
    return operation;
  }
}
