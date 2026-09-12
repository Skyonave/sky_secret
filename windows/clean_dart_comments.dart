import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';

String stripDartComments(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) throw FormatException('Invalid Dart source: ${parsed.errors.first}');
  final ranges = <(int, int)>[];
  final originalTokens = <String>[];
  var token = parsed.unit.beginToken;
  while (true) {
    for (Token? comment = token.precedingComments; comment != null; comment = comment.next) {
      var start = comment.offset;
      var end = comment.end;
      final lineStart = start == 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
      final nextLine = source.indexOf('\n', end);
      final lineEnd = nextLine < 0 ? source.length : nextLine;
      if (source.substring(lineStart, start).trim().isEmpty && source.substring(end, lineEnd).trim().isEmpty) {
        start = lineStart;
        end = nextLine < 0 ? source.length : nextLine + 1;
      }
      ranges.add((start, end));
    }
    originalTokens.add(token.lexeme);
    if (token.isEof) break;
    token = token.next!;
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final output = StringBuffer();
  var position = 0;
  for (final range in ranges) {
    if (range.$1 < position) continue;
    output.write(source.substring(position, range.$1));
    if (range.$1 > 0 && range.$2 < source.length &&
        !RegExp(r'\s').hasMatch(source[range.$1 - 1]) && !RegExp(r'\s').hasMatch(source[range.$2])) {
      output.write(' ');
    }
    position = range.$2;
  }
  output.write(source.substring(position));
  final cleaned = _cleanWhitespace(output.toString());
  final checked = parseString(content: cleaned, throwIfDiagnostics: false);
  if (checked.errors.isNotEmpty) throw const FormatException('Comment removal changed Dart syntax');
  token = checked.unit.beginToken;
  var index = 0;
  while (true) {
    if (token.precedingComments != null || index >= originalTokens.length || token.lexeme != originalTokens[index++]) {
      throw const FormatException('Comment removal changed Dart tokens');
    }
    if (token.isEof) break;
    token = token.next!;
  }
  if (index != originalTokens.length) throw const FormatException('Comment removal changed Dart token count');
  return cleaned;
}

String _cleanWhitespace(String source) {
  final output = StringBuffer();
  var token = parseString(content: source, throwIfDiagnostics: false).unit.beginToken;
  var position = 0;
  while (true) {
    var gap = source.substring(position, token.offset);
    gap = gap.replaceAll(RegExp(r'[\t ]+(?=\r?\n)'), '');
    if (token.isEof) gap = gap.replaceFirst(RegExp(r'[\t ]+$'), '');
    output.write(gap);
    if (token.isEof) break;
    output.write(source.substring(token.offset, token.end));
    position = token.end;
    token = token.next!;
  }
  return output.toString().trimLeft();
}

void main(List<String> paths) {
  final changes = <File, String>{};
  for (final path in paths) {
    final file = File(path);
    final original = file.readAsStringSync();
    final cleaned = stripDartComments(original);
    if (cleaned != original) changes[file] = cleaned;
  }
  for (final entry in changes.entries) {
    entry.key.writeAsStringSync(entry.value);
  }
}
