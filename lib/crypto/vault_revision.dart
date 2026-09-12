import 'dart:math';

import 'vault_cipher.dart';

class VaultRevision {
  final String lineage;
  final int keyEpoch;
  final Map<String, int> clock;
  static final _identifierPattern = RegExp(r'^[0-9a-f]{32}$');
  static const _maxCounter = 9007199254740991;
  static const _maxWriters = 1024;

  VaultRevision(
    this.lineage,
    Map<String, int> clock, {
    this.keyEpoch = 0,
  }) : clock = Map.unmodifiable(clock);

  static String randomId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  factory VaultRevision.fromJson(Object? value) {
    final json = switch (value) {
      Map<String, dynamic> json when json.length == 3 => json,
      _ => throw const VaultFormatException(),
    };
    final lineage = switch (json[_VaultRevisionJson.lineage]) {
      String id when _identifierPattern.hasMatch(id) => id,
      _ => throw const VaultFormatException(),
    };
    final keyEpoch = switch (json[_VaultRevisionJson.keyEpoch]) {
      int epoch when epoch >= 0 && epoch <= _maxCounter => epoch,
      _ => throw const VaultFormatException(),
    };
    final serializedClock = switch (json[_VaultRevisionJson.clock]) {
      Map<String, dynamic> clock when clock.length <= _maxWriters => clock,
      _ => throw const VaultFormatException(),
    };

    final clock = <String, int>{};
    for (final entry in serializedClock.entries) {
      final validWriter = _identifierPattern.hasMatch(entry.key);
      final counter = entry.value;
      if (validWriter && counter is int && counter >= 1 && counter <= _maxCounter) {
        clock[entry.key] = counter;
      } else {
        throw const VaultFormatException();
      }
    }
    return VaultRevision(lineage, clock, keyEpoch: keyEpoch);
  }

  Map<String, dynamic> toJson() => {
    _VaultRevisionJson.lineage: lineage,
    _VaultRevisionJson.clock: clock,
    _VaultRevisionJson.keyEpoch: keyEpoch,
  };

  VaultRevision rotate() => VaultRevision(lineage, clock, keyEpoch: keyEpoch + 1);

  bool includes(VaultRevision other) =>
      lineage == other.lineage && other.clock.entries.every((e) => (clock[e.key] ?? 0) >= e.value);

  bool succeeds(VaultRevision other) => includes(other) && !other.includes(this);

  VaultRevision advance(String writer, {VaultRevision? merge}) {
    if (merge != null && merge.lineage != lineage) {
      throw const VaultFormatException();
    }
    final next = Map<String, int>.of(clock);
    for (final e in merge?.clock.entries ?? <MapEntry<String, int>>[]) {
      next[e.key] = max(next[e.key] ?? 0, e.value);
    }
    next[writer] = (next[writer] ?? 0) + 1;
    return VaultRevision.fromJson({
      _VaultRevisionJson.lineage: lineage,
      _VaultRevisionJson.clock: next,
      _VaultRevisionJson.keyEpoch: keyEpoch,
    });
  }
}

abstract final class _VaultRevisionJson {
  static const lineage = 'lineage';
  static const clock = 'clock';
  static const keyEpoch = 'keyEpoch';
}
