# SkySecret

[Русский](#русский) · [Releases](https://github.com/Skyonave/sky_secret/releases)

A portable password and file manager for Windows. Works offline, lives in the system tray and opens with **Shift+Space**. Built with Flutter and Dart.

<p align="center">
  <img src="assets/screenshots/vault-en.png" width="300" alt="SkySecret vault with demo entries and files">
  <img src="assets/screenshots/generator-en.png" width="300" alt="SkySecret password generator">
</p>

- Multiple vaults with separate master passwords, **Argon2id + AES-256-GCM** encryption, password generation and automatic locking.
- Secrets and files organized into sections and folders, with drag-and-drop and saved manual ordering.
- Create `.txt` files in the vault and edit text in separate windows; **Ctrl+S** saves changes.
- Saved SSH connections through CMD and Windows OpenSSH.
- Encrypted `.smv` import/export, optional GitHub backups and manual sync, conflict review, history and recovery.
- Russian and English interface; configurable visibility in screen recordings.

Run **SkySecret-<version>-windows-x64.exe**, open the manager from the tray and create a vault. **There is no master-password reset.** GitHub is optional; its connection dialog guides repository and token setup. Save edits before hiding the manager: hiding locks it by default.

> We work to protect your data, but cannot guarantee its security or recovery. Keep verified independent backups.

## Русский

Переносной менеджер паролей и файлов для Windows. Работает офлайн, запускается в трее и открывается по **Shift+Space**. Написан на Flutter и Dart.

- Несколько сейфов с отдельными мастер-паролями, шифрование **Argon2id + AES-256-GCM**, генератор паролей и автоблокировка.
- Секреты и файлы в разделах и папках, перетаскивание и сохранение ручного порядка.
- Создание `.txt` внутри сейфа, редактирование текста в отдельных окнах; **Ctrl+S** сохраняет изменения.
- Сохранённые SSH-подключения через CMD и Windows OpenSSH.
- Импорт и экспорт зашифрованных `.smv`, необязательные копии в GitHub и ручная синхронизация, разбор конфликтов, история и восстановление.
- Русский и английский интерфейс, настройка видимости при записи экрана.

Запустите **SkySecret-<версия>-windows-x64.exe**, откройте менеджер из трея и создайте сейф. **Сброса мастер-пароля нет.** GitHub подключается по желанию; настройка репозитория и токена объясняется в диалоге подключения. Сохраняйте правки перед скрытием: по умолчанию оно блокирует сейф.

> Мы максимально стараемся обезопасить данные, но не можем гарантировать их безопасность и восстановление. Храните проверенные независимые резервные копии.

[Security / Безопасность](SECURITY.md) · [License](LICENSE)
