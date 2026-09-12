abstract interface class SensitiveClipboard {
  Future<int> write(String text);

  Future<bool> clearIfCurrent(int revision);
}

class ClipboardUnavailable implements Exception {
  const ClipboardUnavailable();
}
