# SkySecret

[Русский](#русский) · [Releases](https://github.com/Skyonave/sky_secret/releases)

A portable password and file manager for Windows. Works offline, lives in the system tray and opens with **Shift+Space**. Built with Flutter and Dart.

<p align="center">
  <img src="assets/screenshots/vault-en.png" width="300" alt="SkySecret vault with demo entries and files">
  <img src="assets/screenshots/generator-en.png" width="300" alt="SkySecret password generator">
</p>

- Multiple vaults with separate master passwords, **Argon2id + AES-256-GCM** encryption, password generation and automatic locking.
- Secrets and files organized into sections and folders, with drag-and-drop and saved manual ordering.
- Open the manager with **Shift+Space**, unlock your vault, then press **F** to open search in the center of the screen. Type a name, username, server or folder; choose a suggestion with **↑/↓ + Enter** or a click. **Esc** closes search. Mark favorites with a star. Deleted entries go to encrypted trash and can be restored; **Undo** is available immediately after deletion.
- Create `.txt` files in the vault and edit text in separate windows; **Ctrl+S** saves changes.
- Saved SSH connections through CMD and Windows OpenSSH.
- Encrypted `.smv` import/export, optional GitHub backups and manual sync, conflict review, history and recovery.
- Russian and English interface; configurable visibility in screen recordings.

Run **SkySecret-<version>-windows-x64.exe**, open the manager from the tray and create a vault. **There is no master-password reset.** GitHub is optional; its connection dialog guides repository and token setup. Save edits before hiding the manager: hiding locks it by default.

> We work to protect your data, but cannot guarantee its security or recovery. Keep verified independent backups.

Before saving a shared vault in **0.3.1**, update every device to **0.3.1 or later**. Older versions cannot open the updated vault. Keep a verified independent backup before upgrading.

## Русский

Переносной менеджер паролей и файлов для Windows. Работает офлайн, запускается в трее и открывается по **Shift+Space**. Написан на Flutter и Dart.

- Несколько сейфов с отдельными мастер-паролями, шифрование **Argon2id + AES-256-GCM**, генератор паролей и автоблокировка.
- Секреты и файлы в разделах и папках, перетаскивание и сохранение ручного порядка.
- Откройте менеджер через **Shift+Space**, разблокируйте сейф и нажмите **F** — поиск появится в центре экрана. Введите название, логин, сервер или папку; выберите подсказку стрелками **↑/↓ + Enter** или мышью. **Esc** закрывает поиск. Звезда добавляет запись в избранное. Удалённые записи можно восстановить из зашифрованной корзины; сразу после удаления доступно **«Отменить»**.
- Создание `.txt` внутри сейфа, редактирование текста в отдельных окнах; **Ctrl+S** сохраняет изменения.
- Сохранённые SSH-подключения через CMD и Windows OpenSSH.
- Импорт и экспорт зашифрованных `.smv`, необязательные копии в GitHub и ручная синхронизация, разбор конфликтов, история и восстановление.
- Русский и английский интерфейс, настройка видимости при записи экрана.

Запустите **SkySecret-<версия>-windows-x64.exe**, откройте менеджер из трея и создайте сейф. **Сброса мастер-пароля нет.** GitHub подключается по желанию; настройка репозитория и токена объясняется в диалоге подключения. Сохраняйте правки перед скрытием: по умолчанию оно блокирует сейф.

> Мы максимально стараемся обезопасить данные, но не можем гарантировать их безопасность и восстановление. Храните проверенные независимые резервные копии.

Перед сохранением общего сейфа в **0.3.1** обновите все устройства до **0.3.1 или новее**. Старые версии не откроют обновлённый сейф. До обновления сохраните проверенную независимую резервную копию.

[Security / Безопасность](SECURITY.md) · [License](LICENSE)
