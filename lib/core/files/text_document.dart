import 'dart:convert';
import 'dart:typed_data';

class TextDocument {
  final String text;
  final String encoding;
  final String newline;
  static const maxBytes = 2 * 1024 * 1024;
  static const _extensions = {
    'txt',
    'md',
    'markdown',
    'json',
    'csv',
    'tsv',
    'yaml',
    'yml',
    'xml',
    'html',
    'htm',
    'css',
    'js',
    'jsx',
    'ts',
    'tsx',
    'dart',
    'py',
    'ini',
    'cfg',
    'conf',
    'toml',
    'sql',
    'sh',
    'bat',
    'cmd',
    'ps1',
    'log',
    'env',
    'gitignore',
    'c',
    'cpp',
    'h',
    'hpp',
    'java',
    'kt',
    'go',
    'rs',
    'swift',
    'properties',
    'tex',
    'rst',
    'svg',
  };

  TextDocument._(
    this.text,
    this.encoding,
    this.newline,
  );

  static TextDocument? decode(String name, Uint8List bytes) {
    final extension = name.toLowerCase().split('.').last;
    if ((!_extensions.contains(extension) && name.toLowerCase() != 'dockerfile') || bytes.length > maxBytes) {
      return null;
    }
    try {
      String text;
      var encoding = 'UTF-8';
      if (bytes.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) {
        if (bytes.length.isOdd) return null;
        final little = bytes[0] == 0xff;
        encoding = little ? 'UTF-16 LE' : 'UTF-16 BE';
        final data = ByteData.sublistView(bytes);
        final units = [
          for (var i = 2; i < bytes.length; i += 2) data.getUint16(i, little ? Endian.little : Endian.big),
        ];
        for (var i = 0; i < units.length; i++) {
          final unit = units[i];
          if (unit >= 0xd800 && unit <= 0xdbff) {
            if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
              return null;
            }
          } else if (unit >= 0xdc00 && unit <= 0xdfff) {
            return null;
          }
        }
        text = String.fromCharCodes(units);
      } else {
        final bom = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
        encoding = bom ? 'UTF-8 BOM' : 'UTF-8';
        text = utf8.decode(
          bom ? bytes.sublist(3) : bytes,
          allowMalformed: false,
        );
      }
      if (RegExp(r'[\x00-\x08\x0b\x0e-\x1f]').hasMatch(text)) return null;
      final newline = text.contains('\r\n') ? '\r\n' : (text.contains('\r') ? '\r' : '\n');
      return TextDocument._(
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
        encoding,
        newline,
      );
    } on FormatException {
      return null;
    }
  }

  Uint8List encode(String edited) {
    if (edited.length > maxBytes) throw const FormatException('Text too large');
    final text = edited.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', newline);
    final Uint8List result;
    if (encoding.startsWith('UTF-16')) {
      final little = encoding == 'UTF-16 LE';
      result = Uint8List(2 + text.length * 2);
      final data = ByteData.sublistView(result);
      data.setUint16(0, 0xfeff, little ? Endian.little : Endian.big);
      for (var i = 0; i < text.length; i++) {
        data.setUint16(
          2 + i * 2,
          text.codeUnitAt(i),
          little ? Endian.little : Endian.big,
        );
      }
    } else {
      result = Uint8List.fromList([
        if (encoding == 'UTF-8 BOM') ...[0xef, 0xbb, 0xbf],
        ...utf8.encode(text),
      ]);
    }
    if (result.length > maxBytes) throw const FormatException('Text too large');
    return result;
  }
}
