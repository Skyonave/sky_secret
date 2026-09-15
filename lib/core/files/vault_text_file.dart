import '../crypto/crypto.dart';

enum TextFileProblem { invalidName, nameTaken, limit, location }

class TextFileException implements Exception {
  final TextFileProblem problem;

  const TextFileException(this.problem);
}

abstract final class VaultTextFile {
  static String fileName(String input) {
    final name = input.trim();
    final stem = name.toLowerCase().endsWith('.txt') ? name.substring(0, name.length - 4) : name;
    if (!VaultAttachment.validName(stem) || !VaultAttachment.validName('$stem.txt')) {
      throw const TextFileException(TextFileProblem.invalidName);
    }
    return '$stem.txt';
  }

  static VaultEntry prepare({
    required String name,
    required VaultOrganization organization,
    String? folderId,
  }) {
    final normalized = fileName(name);
    if (folderId != null && !organization.folders.any((folder) => folder.id == folderId)) {
      throw const TextFileException(TextFileProblem.location);
    }
    if (organization.entries.any(
      (entry) => entry.isFile && entry.folderId == folderId && entry.title.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const TextFileException(TextFileProblem.nameTaken);
    }
    if (organization.entries.where((entry) => entry.isFile).length >= VaultCipher.maxFiles) {
      throw const TextFileException(TextFileProblem.limit);
    }
    final entry = VaultEntry.file(VaultAttachment.create(normalized, const []), folderId: folderId);
    organization.prependEntries([entry], folderId);
    return organization.entries.firstWhere((candidate) => candidate.id == entry.id);
  }
}
