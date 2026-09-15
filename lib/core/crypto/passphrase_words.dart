class PassphraseWords {
  final List<String> words;

  PassphraseWords._(this.words);

  factory PassphraseWords.parse(String source) {
    final words = <String>[];
    final codes = <String>{};
    for (final line in source.split('\n')) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(r'^([1-6]{5})\s+([a-z]+(?:-[a-z]+)?)$').firstMatch(line.trim());
      if (match == null || !codes.add(match[1]!)) throw const FormatException('Invalid passphrase word list');
      words.add(match[2]!);
    }
    if (words.length != 7776 || words.toSet().length != 7776) {
      throw const FormatException('Incomplete passphrase word list');
    }
    return PassphraseWords._(List.unmodifiable(words));
  }
}
