import 'dart:convert';
import 'dart:io';

class SshEndpoint {
  final String host;
  final int port;

  const SshEndpoint({required this.host, this.port = 22});

  bool get isValid {
    if (port < 1 || port > 65535 || host.isEmpty || host.length > 253) {
      return false;
    }
    if (host.contains(':')) {
      return InternetAddress.tryParse(host)?.type == InternetAddressType.IPv6;
    }
    return host
        .split('.')
        .every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label),
        );
  }

  static bool validUsername(String value) =>
      value.length <= 128 && RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.-]*\$?$').hasMatch(value);

  static bool validPassword(String value) =>
      value.isNotEmpty && utf8.encode(value).length <= 1000 && !RegExp(r'[\x00\r\n]').hasMatch(value);

  Map<String, dynamic> toJson() => {'host': host, 'port': port};
}
