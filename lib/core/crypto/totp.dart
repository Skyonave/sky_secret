import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class TotpConfiguration {
  final String secret;
  final String algorithm;
  final int digits;
  final int period;

  const TotpConfiguration._(this.secret, this.algorithm, this.digits, this.period);

  factory TotpConfiguration.parse(String input) {
    try {
      return TotpConfiguration._parse(input);
    } on FormatException {
      throw const FormatException('Invalid TOTP configuration');
    }
  }

  static TotpConfiguration _parse(String input) {
    if (input.length > 4096) throw const FormatException('Invalid TOTP configuration');
    var secret = input.trim();
    var algorithm = 'SHA1';
    var digits = 6;
    var period = 30;
    if (secret.contains('://')) {
      final uri = Uri.tryParse(secret);
      if (uri == null ||
          uri.scheme != 'otpauth' ||
          uri.host != 'totp' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasFragment ||
          uri.path.length < 2) {
        throw const FormatException('Invalid TOTP configuration');
      }
      final parameters = uri.queryParametersAll;
      if (parameters.values.any((values) => values.length != 1) ||
          parameters.keys.any((key) => !['secret', 'issuer', 'algorithm', 'digits', 'period'].contains(key))) {
        throw const FormatException('Invalid TOTP configuration');
      }
      secret = uri.queryParameters['secret'] ?? '';
      algorithm = (uri.queryParameters['algorithm'] ?? 'SHA1').toUpperCase();
      digits = int.tryParse(uri.queryParameters['digits'] ?? '6') ?? 0;
      period = int.tryParse(uri.queryParameters['period'] ?? '30') ?? 0;
    }
    if (!['SHA1', 'SHA256', 'SHA512'].contains(algorithm) || ![6, 8].contains(digits) || period < 1 || period > 300) {
      throw const FormatException('Invalid TOTP configuration');
    }
    secret = secret.toUpperCase().replaceAll(RegExp(r'\s'), '');
    final decoded = _decodeBase32(secret);
    decoded.fillRange(0, decoded.length, 0);
    secret = secret.replaceAll('=', '');
    return TotpConfiguration._(secret, algorithm, digits, period);
  }

  String get uri => Uri(
    scheme: 'otpauth',
    host: 'totp',
    path: '/SkySecret',
    queryParameters: {'secret': secret, 'algorithm': algorithm, 'digits': '$digits', 'period': '$period'},
  ).toString();

  int remainingSeconds(DateTime time) => period - (time.millisecondsSinceEpoch ~/ 1000) % period;

  Future<String> codeAt(DateTime time) async {
    if (time.millisecondsSinceEpoch < 0) throw const FormatException('Invalid TOTP time');
    final bytes = _decodeBase32(secret);
    final key = SecretKeyData(bytes, overwriteWhenDestroyed: true);
    final counter = ByteData(8)..setUint64(0, time.millisecondsSinceEpoch ~/ 1000 ~/ period);
    final hmac = switch (algorithm) {
      'SHA256' => Hmac.sha256(),
      'SHA512' => Hmac.sha512(),
      _ => Hmac.sha1(),
    };
    try {
      final mac = await hmac.calculateMac(counter.buffer.asUint8List(), secretKey: key);
      final offset = mac.bytes.last & 15;
      final number =
          ((mac.bytes[offset] & 127) << 24) |
          (mac.bytes[offset + 1] << 16) |
          (mac.bytes[offset + 2] << 8) |
          mac.bytes[offset + 3];
      return (number % (digits == 8 ? 100000000 : 1000000)).toString().padLeft(digits, '0');
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Uint8List _decodeBase32(String value) {
    final match = RegExp(r'^([A-Z2-7]+)(=*)$').firstMatch(value);
    if (match == null) throw const FormatException('Invalid TOTP secret');
    final symbols = match.group(1)!;
    final padding = match.group(2)!.length;
    if (![0, 2, 4, 5, 7].contains(symbols.length % 8) || (padding > 0 && padding != (8 - symbols.length % 8) % 8)) {
      throw const FormatException('Invalid TOTP secret');
    }
    final length = symbols.length * 5 ~/ 8;
    if (length < 10 || length > 128) throw const FormatException('Invalid TOTP secret');
    final bytes = Uint8List(length);
    var buffer = 0;
    var bits = 0;
    var index = 0;
    for (final symbol in symbols.codeUnits) {
      final digit = symbol >= 65 ? symbol - 65 : symbol - 50 + 26;
      buffer = (buffer << 5) | digit;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes[index++] = (buffer >> bits) & 255;
        buffer &= (1 << bits) - 1;
      }
    }
    if (buffer != 0) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('Invalid TOTP secret');
    }
    return bytes;
  }
}
