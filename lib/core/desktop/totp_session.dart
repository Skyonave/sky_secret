import '../crypto/crypto.dart';

class TotpSession {
  final VaultSession vault;
  final bool Function() isValid;
  final Future<bool> Function(String) copy;
  final Future<void> Function() clearClipboard;
  final void Function() activity;
  bool _closed = false;

  TotpSession({
    required this.vault,
    required this.isValid,
    required this.copy,
    required this.clearClipboard,
    required this.activity,
  });

  bool get valid => _closed == false && vault.isLocked == false && isValid();

  Future<List<Map<String, Object>>> snapshot(DateTime time) async {
    if (valid == false) return [];
    final rows = <Map<String, Object>>[];
    final entries = vault.entries;
    for (final entry in entries) {
      if (entry.isDeleted || entry.hasTotp == false) continue;
      final config = TotpConfiguration.parse(entry.totp);
      final code = await config.codeAt(time);
      if (valid == false) return [];
      rows.add({
        'id': entry.id,
        'title': entry.title,
        'username': entry.username,
        'code': code,
        'period': config.period,
        'expires': (time.millisecondsSinceEpoch ~/ (config.period * 1000) + 1) * config.period * 1000,
      });
    }
    if (valid == false) return [];
    final current = vault.entries;
    if (entries.length != current.length) return [];
    for (var index = 0; index < entries.length; index++) {
      if (!identical(entries[index], current[index])) return [];
    }
    return rows;
  }

  Future<bool> copyCode(String id, DateTime time) async {
    if (valid == false) return false;
    final entry = vault.entries.where((entry) => entry.id == id && entry.isDeleted == false).firstOrNull;
    if (entry == null || entry.hasTotp == false) return false;
    final code = await TotpConfiguration.parse(entry.totp).codeAt(time);
    if (valid == false || vault.entries.contains(entry) == false) return false;
    activity();
    final copied = await copy(code);
    if (valid == false || vault.entries.contains(entry) == false) {
      await clearClipboard();
      return false;
    }
    return copied;
  }

  void close() => _closed = true;
}
