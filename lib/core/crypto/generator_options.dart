enum GeneratorMode { password, passphrase }

class GeneratorOptions {
  final GeneratorMode mode;
  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;
  final bool excludeSimilar;
  final int wordCount;
  final String separator;

  const GeneratorOptions({
    this.mode = GeneratorMode.password,
    this.length = 24,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.excludeSimilar = false,
    this.wordCount = 6,
    this.separator = '-',
  });

  bool get valid =>
      length >= 12 &&
      length <= 64 &&
      wordCount >= 6 &&
      wordCount <= 10 &&
      const ['-', ' ', '_', '.'].contains(separator) &&
      (mode == GeneratorMode.passphrase || lowercase || uppercase || digits || symbols);

  GeneratorOptions copyWith({
    GeneratorMode? mode,
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? excludeSimilar,
    int? wordCount,
    String? separator,
  }) => GeneratorOptions(
    mode: mode ?? this.mode,
    length: length ?? this.length,
    lowercase: lowercase ?? this.lowercase,
    uppercase: uppercase ?? this.uppercase,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    excludeSimilar: excludeSimilar ?? this.excludeSimilar,
    wordCount: wordCount ?? this.wordCount,
    separator: separator ?? this.separator,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'mode': mode.name,
    'length': length,
    'lowercase': lowercase,
    'uppercase': uppercase,
    'digits': digits,
    'symbols': symbols,
    'excludeSimilar': excludeSimilar,
    'wordCount': wordCount,
    'separator': separator,
  };

  factory GeneratorOptions.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        !GeneratorMode.values.any((mode) => mode.name == value['mode']) ||
        value['length'] is! int ||
        value['wordCount'] is! int ||
        value['separator'] is! String ||
        !['lowercase', 'uppercase', 'digits', 'symbols', 'excludeSimilar'].every((key) => value[key] is bool)) {
      throw const FormatException('Invalid generator preferences');
    }
    final result = GeneratorOptions(
      mode: GeneratorMode.values.byName(value['mode'] as String),
      length: value['length'] as int,
      lowercase: value['lowercase'] as bool,
      uppercase: value['uppercase'] as bool,
      digits: value['digits'] as bool,
      symbols: value['symbols'] as bool,
      excludeSimilar: value['excludeSimilar'] as bool,
      wordCount: value['wordCount'] as int,
      separator: value['separator'] as String,
    );
    if (!result.valid) throw const FormatException('Invalid generator preferences');
    return result;
  }
}
