part of 'vault_cipher.dart';

class VaultFolder {
  final String id;
  final String name;
  final String? parentId;
  final int order;

  const VaultFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.order = 0,
  });

  factory VaultFolder.create(
    String name, {
    String? parentId,
    int order = 0,
  }) => VaultFolder(id: base64UrlEncode(_randomBytes(16)), name: name.trim(), parentId: parentId, order: order);

  bool get isSection => parentId == null;

  VaultFolder atPosition(String? parentId, int order) =>
      VaultFolder(id: id, name: name, parentId: parentId, order: order);

  Map<String, dynamic> toJson() => {
    _VaultFolderJson.id: id,
    _VaultFolderJson.name: name,
    _VaultFolderJson.parentId: parentId,
    _VaultFolderJson.order: order,
  };

  static VaultFolder fromJson(dynamic value, {bool organized = true}) {
    if (organized && value is Map<String, dynamic> && value.length == 4) {
      if (!_validOrder(value[_VaultFolderJson.order]) ||
          (value[_VaultFolderJson.parentId] != null && value[_VaultFolderJson.parentId] is! String) ||
          !value.containsKey(_VaultFolderJson.parentId)) {
        throw const VaultFormatException();
      }
      final folder = fromJson(
        {...value}
          ..remove(_VaultFolderJson.parentId)
          ..remove(_VaultFolderJson.order),
        organized: false,
      );
      return folder.atPosition(value[_VaultFolderJson.parentId] as String?, value[_VaultFolderJson.order] as int);
    }
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        value[_VaultFolderJson.id] is! String ||
        (value[_VaultFolderJson.id] as String).isEmpty ||
        (value[_VaultFolderJson.id] as String).length > 64 ||
        value[_VaultFolderJson.id] == '*' ||
        value[_VaultFolderJson.name] is! String ||
        (value[_VaultFolderJson.name] as String).trim().isEmpty ||
        (value[_VaultFolderJson.name] as String).length > 120) {
      throw const VaultFormatException();
    }
    return VaultFolder(id: value[_VaultFolderJson.id], name: value[_VaultFolderJson.name]);
  }
}

abstract final class _VaultFolderJson {
  static const id = 'id';
  static const order = 'order';
  static const name = 'name';
  static const parentId = 'parentId';
}
