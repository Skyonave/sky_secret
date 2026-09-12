part of 'vault_panel.dart';

class _VaultEntryDraft {
  final title = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final notes = TextEditingController();
  final sshHost = TextEditingController();
  final sshPort = TextEditingController(text: '22');

  List<TextEditingController> get _controllers => [title, username, password, notes, sshHost, sshPort];

  void clear() {
    for (final controller in _controllers) {
      controller.clear();
    }
  }

  void dispose() {
    for (final controller in _controllers) {
      controller.clear();
      controller.dispose();
    }
  }
}
