# Security / Безопасность

## Protection and limits

SkySecret encrypts vault contents with AES-256-GCM and derives the wrapping key from the master password using Argon2id v19 (64 MiB, three iterations, four lanes). GitHub credentials are separate from vault encryption and protected locally with Windows DPAPI. Encrypted writes use atomic replacement and conflict checks; authentication failures never create an empty replacement vault.

The application reduces exposure through automatic locking, protected memory buffers, clipboard expiry, capture controls and restricted native interfaces. These measures also target local malware, but cannot reliably stop an attacker controlling the user session or OS: input, displayed secrets and unlocked process memory can be captured. Clipboard copies, screen recordings, exported plaintext and remote backups require care. Locking clears owned buffers; Dart strings and copies made by Windows or other software cannot all be reliably erased. Keep verified independent backups. We work to protect data, but cannot guarantee its security or recovery.

## Passwords and compatibility in 0.2.0

- New master passwords need at least 16 characters. Long unique passphrases are accepted without mandatory uppercase, digits or symbols; obvious values and repeated patterns are rejected. Unlocking and importing existing vaults do not apply this policy.
- New vaults and password changes use envelope v2: NFC-normalized Unicode passwords and an allowlisted KDF profile. Unknown profiles are rejected before expensive derivation. Update every device to **0.2.0 or later** before creating or rotating a shared vault. Existing v1 vaults retain exact UTF-8 password bytes when opened or saved; password change migrates them to v2.
- Limits: 1,000 password/SSH entries, 5,000 files, 100 folders; 20 MiB per file, 50 MiB total file contents, 72 MiB encrypted vault. Oversized vaults are rejected without truncation or replacement. If an older vault exceeds the new file count, use its earlier compatible application to split it into smaller verified vaults first.

## Favorites and trash in 0.3.1

The file editor receives document contents only after Windows confirms the configured capture policy. If that setup fails, the editor closes without loading the document. Editor save/copy messages are bounded, and a clipboard write completed after session revocation is cleared when possible and reported as unsuccessful.

Version **0.3.1** saves payload schema 8. Favorites and trash metadata are encrypted with each entry; opening an older vault alone does not rewrite it. Update all devices before saving with 0.3.1: earlier applications reject schema 8. Trash counts toward existing entry and attachment limits, has no automatic expiry, and is included in encrypted exports and sync. Permanent removal affects the current vault; recovery history and external backups may retain copies. Search reads only the unlocked vault's titles, usernames, SSH hosts and folder names, without indexing passwords, notes or file contents on disk.

## Changing a compromised password

A password change generates a fresh data key and removes managed local recovery history and sync caches after the new vault commits. An interrupted or failed cleanup leaves a retry marker and a visible warning; close software holding the snapshots and reopen the vault to retry. Ordinary edits resume local recovery history under the new key.

Synchronization stops when a revision uses a different key envelope, even if it claims a higher key epoch. It never automatically encrypts local entries with that revision’s key or requests an alternative password to permit merging. Keep the local vault, or restore the remote copy as a separate vault for review. Restoring separately preserves the original vault and its synchronization link.

Text input Copy/Cut uses the protected clipboard path; revealed conflict passwords use the explicit Copy button. IME personalized learning is disabled for text inputs. Clipboard expiration is best-effort: abnormal process or OS termination can prevent timed clearing of its current contents.

Old exports and GitHub commits **remain decryptable with the old password**. A change cannot revoke downloaded copies, filesystem backups or recoverable storage remnants. If the password was exposed, verify a fresh independent backup, use a replacement backup repository on every device, and deal separately with the old repository and its copies. Rotate exposed account passwords and SSH credentials as well. SkySecret never silently rewrites remote Git history.

## Verifying a release

Release attachments are the portable EXE and `verification.zip`. The ZIP contains `attestation.sigstore.json` and `build-verification.zip`; the latter contains checksums, dependency inventory and build information. Both the EXE and the inner ZIP are attested by the tagged GitHub workflow. The outer ZIP is only a container. **Authenticode signing is not provided.** Attestation establishes workflow provenance and integrity, not absence of vulnerabilities or reproducible builds.

After extracting `verification.zip`, verify both subjects with [GitHub CLI](https://cli.github.com/manual/gh_attestation_verify). Replace `<version>` with the release version (for example, `0.3.1`) and `<commit>` with the full commit shown for that release tag on GitHub:

```powershell
$policy = @('--repo', 'Skyonave/sky_secret', '--bundle', 'attestation.sigstore.json', '--signer-workflow', 'Skyonave/sky_secret/.github/workflows/release.yml', '--source-ref', 'refs/tags/v<version>', '--source-digest', '<commit>', '--signer-digest', '<commit>', '--deny-self-hosted-runners')
gh attestation verify SkySecret-<version>-windows-x64.exe @policy
gh attestation verify build-verification.zip @policy
```

Both commands must succeed. Extract the verified inner ZIP to inspect its build information. Do not treat a checksum supplied alongside an unverified file as proof of origin.

## Русский

Редактор файлов получает содержимое только после подтверждения настроенной политики захвата окна Windows. При ошибке настройки редактор закрывается без загрузки документа. Размер сообщений сохранения и копирования ограничен; запись в буфер, завершившаяся после отзыва сессии, по возможности очищается и считается неуспешной.

Версия **0.3.1** сохраняет данные по схеме 8. Избранное и сведения о корзине шифруются вместе с записями; одно открытие старого сейфа не меняет файл. Перед сохранением в 0.3.1 обновите все устройства: прежние приложения отвергают схему 8. Корзина учитывается в существующих лимитах записей и вложений, не очищается автоматически и входит в зашифрованный экспорт и синхронизацию. Окончательное удаление меняет текущий сейф; история восстановления и внешние копии могут сохранять запись. Поиск использует только названия, логины, SSH-адреса и имена папок открытого сейфа; пароли, заметки и содержимое файлов не индексируются на диске.

Содержимое сейфа защищают AES-256-GCM и Argon2id v19 (64 МиБ, три прохода, четыре линии). Учётные данные GitHub отделены от шифрования сейфа и локально защищены Windows DPAPI. Атомарная запись и проверка версий снижают риск повреждения и потери правок. Ошибка доступа или расшифровки не заменяет сейф пустым.

Автоблокировка, защищённые буферы, очистка буфера обмена, управление захватом окон и ограничения нативных интерфейсов снижают риск утечки, в том числе от вредоносного ПО. Они не гарантируют защиту при контроле атакующим сеанса пользователя или ОС. Возможен перехват ввода, экрана и памяти открытого сейфа; строки Dart, копии Windows и других программ нельзя надёжно стереть все. Экспортированный открытый текст и внешние копии требуют отдельной защиты. Мы максимально стараемся обезопасить данные, но не можем гарантировать их безопасность и восстановление. Храните проверенные независимые копии.

В **0.2.0** новые мастер-пароли требуют 16 символов; подходят длинные уникальные фразы без обязательных цифр, регистра и спецсимволов. Очевидные значения и повторения отклоняются. Старые пароли остаются пригодными для открытия и импорта. Новые сейфы и смена пароля используют формат v2 с NFC и проверяемым профилем KDF. Перед этим обновите все устройства до 0.2.0 или новее. Открытие и обычное сохранение v1 оставляют пароль побайтно прежним; смена пароля переводит сейф в v2.

Пределы: 1 000 записей паролей/SSH, 5 000 файлов, 100 папок; 20 МиБ на файл, 50 МиБ суммарно, 72 МиБ на зашифрованный сейф. Превышающий предел сейф не усекается и не заменяется. Слишком большой старый сейф сначала разделите на проверенные небольшие сейфы в прежней совместимой версии приложения.

Смена пароля создаёт новый ключ данных и после успешной записи удаляет локальную историю восстановления и кэш синхронизации. При сбое очистки приложение предупреждает и повторяет её при открытии. Закройте программы, удерживающие снимки, и откройте сейф снова. Последующие правки создают историю уже под новым ключом.

Синхронизация останавливается при другом ключевом конверте, даже если версия заявляет более высокий keyEpoch. Локальные записи не шифруются ключом такой версии автоматически; ввод другого пароля не разрешает объединение. Можно оставить локальный сейф или восстановить удалённую копию отдельным сейфом для проверки. Отдельное восстановление сохраняет исходный сейф и его привязку синхронизации.

Copy/Cut в текстовых полях проходят через защищённый буфер обмена; раскрытый пароль конфликта копируется отдельной кнопкой. Персонализированное обучение IME отключено для текстовых полей. Очистка буфера по таймеру выполняется по возможности: аварийное завершение приложения или ОС может помешать удалению текущего содержимого.

**Старые экспорты и коммиты GitHub продолжают открываться старым паролем.** Скачанные копии, резервные копии диска и остатки на носителе не отзываются. При компрометации проверьте новую независимую копию, замените репозиторий резервирования на всех устройствах и отдельно разберитесь со старым репозиторием и копиями. Смените также раскрытые пароли аккаунтов и SSH. Приложение не переписывает Git-историю автоматически.

В релизе только EXE и `verification.zip`. Внутри — attestation и подписанный вложенный архив с контрольными суммами и сведениями о сборке. Выполните обе команды выше, подставив номер выпуска вместо `<version>` и полный коммит тега вместо `<commit>`; обе должны завершиться успешно. Подписи **Authenticode нет**. GitHub attestation подтверждает происхождение файлов из workflow и их целостность, но не отсутствие уязвимостей и не воспроизводимость сборки.
