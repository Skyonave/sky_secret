import 'vault_cipher.dart';

class VaultItem {
  final VaultEntry? entry;
  final VaultFolder? folder;

  const VaultItem.entry(VaultEntry this.entry) : folder = null;

  const VaultItem.folder(VaultFolder this.folder) : entry = null;

  String get id => entry?.id ?? folder!.id;

  String get key => '${entry == null ? 'folder' : 'entry'}:$id';

  String get name => entry?.title ?? folder!.name;

  String? get parentId => entry?.folderId ?? folder?.parentId;

  int get order => entry?.order ?? folder!.order;
}

class VaultOrganization {
  final List<VaultEntry> entries;
  final List<VaultFolder> folders;

  VaultOrganization({required List<VaultEntry> entries, required List<VaultFolder> folders})
    : entries = List.of(entries),
      folders = List.of(folders);

  List<VaultItem> children(String? parentId) {
    final items = [
      for (final entry in entries)
        if (entry.folderId == parentId) VaultItem.entry(entry),
      for (final folder in folders)
        if (folder.parentId == parentId) VaultItem.folder(folder),
    ];
    items.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    return items;
  }

  bool canMove(VaultItem item, String? parentId) {
    if (item.entry == null) {
      final matches = folders.where((folder) => folder.id == item.id);
      if (matches.isEmpty) return false;
      final folder = matches.single;
      if (folder.isSection) return parentId == null;
      return folders.any((parent) => parent.id == parentId && parent.isSection);
    }
    if (entries.every((entry) => entry.id != item.id)) return false;
    return parentId == null || folders.any((folder) => folder.id == parentId);
  }

  void move(
    VaultItem item,
    String? parentId, {
    String? beforeKey,
  }) {
    if (!canMove(item, parentId)) throw const VaultFormatException();
    if (beforeKey == item.key) return;
    final siblings = children(parentId)..removeWhere((child) => child.key == item.key);
    final index = beforeKey == null ? siblings.length : siblings.indexWhere((child) => child.key == beforeKey);
    if (index < 0) throw const VaultFormatException();
    siblings.insert(index, item);
    final previous = index == 0 ? -1 : siblings[index - 1].order;
    final next = index + 1 == siblings.length ? previous + 2048 : siblings[index + 1].order;
    if (next - previous > 1 && next <= 9007199254740991) {
      _position(item, parentId, previous + (next - previous) ~/ 2);
      return;
    }
    _renumber(siblings, parentId);
  }

  void appendEntries(List<VaultEntry> added, String? parentId) {
    if (parentId != null && folders.every((folder) => folder.id != parentId)) throw const VaultFormatException();
    final siblings = children(parentId);
    var order = siblings.isEmpty ? 0 : siblings.last.order + 1024;
    if (order + added.length * 1024 > 9007199254740991) {
      _renumber(siblings, parentId);
      order = siblings.length * 1024;
    }
    for (final entry in added) {
      entries.add(entry.atPosition(parentId, order));
      order += 1024;
    }
  }

  void deleteFolder(VaultFolder folder) {
    final removedIds = {
      folder.id,
      for (final child in folders)
        if (child.parentId == folder.id) child.id,
    };
    final moved = entries.where((entry) => removedIds.contains(entry.folderId)).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    folders.removeWhere((item) => removedIds.contains(item.id));
    entries.removeWhere((entry) => removedIds.contains(entry.folderId));
    appendEntries(moved, folder.parentId);
  }

  void _renumber(List<VaultItem> items, String? parentId) {
    final orders = {for (var index = 0; index < items.length; index++) items[index].key: index * 1024};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final order = orders['entry:${entry.id}'];
      if (order != null) entries[index] = entry.atPosition(parentId, order);
    }
    for (var index = 0; index < folders.length; index++) {
      final folder = folders[index];
      final order = orders['folder:${folder.id}'];
      if (order != null) folders[index] = folder.atPosition(parentId, order);
    }
  }

  void _position(
    VaultItem item,
    String? parentId,
    int order,
  ) {
    if (item.entry == null) {
      final index = folders.indexWhere((folder) => folder.id == item.id);
      folders[index] = folders[index].atPosition(parentId, order);
    } else {
      final index = entries.indexWhere((entry) => entry.id == item.id);
      entries[index] = entries[index].atPosition(parentId, order);
    }
  }
}
