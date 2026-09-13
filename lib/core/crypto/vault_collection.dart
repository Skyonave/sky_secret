import 'vault_cipher.dart';

class VaultCollection {
  final List<VaultEntry> entries;
  final List<VaultFolder> folders;

  VaultCollection({required List<VaultEntry> entries, required this.folders}) : entries = List.of(entries);

  List<VaultEntry> get active => entries.where((entry) => entry.isDeleted == false).toList();
  List<VaultEntry> get trash => entries.where((entry) => entry.isDeleted).toList();

  VaultEntry? find(String id) => entries.where((entry) => entry.id == id).firstOrNull;

  bool favorite(String id, bool value) => _replace(id, (entry) => entry.withFavorite(value));

  bool delete(String id, int timestamp) => _replace(id, (entry) => entry.inTrash(timestamp));

  bool restore(String id) => _replace(id, (entry) {
    final folderExists = folders.any((folder) => folder.id == entry.folderId);
    return entry.inTrash(null).inFolder(folderExists ? entry.folderId : null);
  });

  bool purge(String id) {
    final entry = find(id);
    if (entry == null || entry.isDeleted == false) return false;
    entries.removeWhere((candidate) => candidate.id == id);
    return true;
  }

  void emptyTrash() => entries.removeWhere((entry) => entry.isDeleted);

  bool _replace(String id, VaultEntry Function(VaultEntry) update) {
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return false;
    entries[index] = update(entries[index]);
    return true;
  }
}
