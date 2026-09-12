import 'package:flutter_test/flutter_test.dart';

import '../windows/clean_dart_comments.dart';

void main() {
  test('cleanup preserves URLs, raw strings, interpolation and nested literals', () {
    const source = r"""
// header
const address = 'https://example.invalid/path#fragment';
const pattern = r'/* this is data */ // also data';
final value = '${{'path': '/* literal */'}['path']}';
/* outer /* nested */ comment */
int/* separator */valueWithComment = 2; // trailing
const unicode = 'Синтетический текст 🔐';
// end
""";
    final cleaned = stripDartComments(source);
    expect(cleaned, contains('https://example.invalid/path#fragment'));
    expect(cleaned, contains("r'/* this is data */ // also data'"));
    expect(cleaned, contains("'/* literal */'"));
    expect(cleaned, contains('int valueWithComment'));
    expect(cleaned, contains('Синтетический текст 🔐'));
    expect(cleaned, isNot(contains('outer')));
    expect(cleaned, isNot(contains('// header')));
    expect(stripDartComments(cleaned), cleaned);
  });

  test('cleanup preserves multiline string spaces and line endings', () {
    const source = "/// Header\r\nconst text = '''first  \r\n// literal\r\nlast''';  \r\n/* tail */";
    final cleaned = stripDartComments(source);
    expect(cleaned, contains("'''first  \r\n// literal\r\nlast'''"));
    expect(cleaned, isNot(contains('Header')));
    expect(cleaned, isNot(contains('tail')));
    expect(cleaned, isNot(contains(";  \r\n")));
  });

  test('comment-free source retains token separators and indentation', () {
    const source = 'void main() {\n  final value = 2;\n  print(value);\n}\n';
    expect(stripDartComments(source), source);
  });
}
