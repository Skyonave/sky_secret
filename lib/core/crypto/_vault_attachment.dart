part of 'vault_cipher.dart';

class VaultAttachment {
  final String id;
  final String name;
  late final ProtectedBytes _bytes;

  factory VaultAttachment._owned(
    VaultAttachment source,
    SecretLifetime lifetime,
  ) {
    final bytes = source._bytes.ownFor(lifetime);
    return identical(bytes, source._bytes) ? source : VaultAttachment._protected(source.id, source.name, bytes);
  }

  VaultAttachment._protected(
    this.id,
    this.name,
    this._bytes,
  );

  VaultAttachment({
    required this.id,
    required this.name,
    required List<int> bytes,
  }) {
    if (id.isEmpty || id.length > 64 || !validName(name) || bytes.length > VaultCipher.maxAttachmentBytes) {
      throw const VaultFormatException();
    }
    _bytes = ProtectedBytes(bytes);
  }

  factory VaultAttachment.create(String name, List<int> bytes) => VaultAttachment(
    id: base64UrlEncode(_randomBytes(16)),
    name: name,
    bytes: bytes,
  );

  int get size => _bytes.length;

  Uint8List get bytes => _bytes.read();

  static bool validName(String name) =>
      name.isNotEmpty &&
      name.length <= 240 &&
      !RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !RegExp(
        r'^(CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(name);

  Map<String, dynamic> toJson() {
    final plain = bytes;
    try {
      return {_VaultAttachmentJson.id: id, _VaultAttachmentJson.name: name, 'data': base64Encode(plain)};
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  static VaultAttachment fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        value[_VaultAttachmentJson.id] is! String ||
        value[_VaultAttachmentJson.name] is! String ||
        value['data'] is! String ||
        (value['data'] as String).length > ((VaultCipher.maxAttachmentBytes + 2) ~/ 3) * 4) {
      throw const VaultFormatException();
    }
    final plain = base64Decode(value['data']);
    try {
      return VaultAttachment(
        id: value[_VaultAttachmentJson.id],
        name: value[_VaultAttachmentJson.name],
        bytes: plain,
      );
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }
}

abstract final class _VaultAttachmentJson {
  static const id = 'id';
  static const name = 'name';
}
