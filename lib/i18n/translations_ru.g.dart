part of 'translations.g.dart';

typedef TranslationsRu = Translations;

class Translations with BaseTranslations<AppLocale, Translations> {
  static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

  Translations({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.ru,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ) {
    _meta.setFlatMapFunction(_flatMapFunction);
  }

  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  dynamic operator [](String key) => _meta.getTranslation(key);

  late final Translations _root = this;

  Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) =>
      Translations(meta: meta ?? this.$meta);

  String get vaultCreateTextFile => 'Создать .txt';

  String get vaultCreateText => 'Создать';

  String get vaultTextFileName => 'Имя файла';

  String get vaultTextDefaultName => 'Новый документ';

  String get vaultTextNameInvalid => 'Введите допустимое имя файла. Расширение .txt добавится автоматически.';

  String get vaultTextNameTaken => 'Здесь уже есть файл с таким именем. Выберите другое.';

  String get vaultSecretKind => 'Секрет';

  String get vaultRoot => 'Без раздела';

  String get vaultContents => 'Содержимое';

  String get vaultLocation => 'Расположение';

  String get vaultLocationActions => 'Действия';

  String get vaultNewSubfolder => 'Создать папку';

  String get vaultRenameSubfolder => 'Переименовать папку';

  String get vaultSubfolderName => 'Название папки';

  String get vaultDeleteSubfolder => 'Удалить папку';

  String vaultDeleteSubfolderQuestion({required Object name}) =>
      'Удалить папку «${name}»? Все её файлы и секреты останутся в разделе.';

  String get vaultRootDropHint => 'Добавляйте файлы и секреты прямо сюда или создайте свой раздел.';

  String get vaultFolderDropHint => 'Перетащите сюда файлы или секреты. Добавление также доступно в меню.';

  String get vaultMoveToRoot => 'Переместить в корень сейфа';

  String get vaultChoose => 'Выбрать сейф';

  String get vaultGeneral => 'Общее';

  String get vaultPasswordOptions => 'Настройки пароля';

  String vaultPasswordLength({required Object length}) => 'Пароль · ${length} симв.';

  String get vaultGeneratePassword => 'Сгенерировать';

  String get vaultNew => 'Создать ещё один сейф';

  String get vaultPrimary => 'Основной сейф';

  String vaultIdentifier({required Object id}) => 'Сейф · ${id}';

  String get vaultDelete => 'Удалить';

  String get vaultDeleteEntry => 'Удалить запись';

  String vaultDeleteEntryQuestion({required Object name}) => 'Удалить «${name}»? Это действие нельзя отменить.';

  String get vaultEditEntry => 'Редактировать запись';

  String get vaultFolders => 'Разделы';

  String get vaultFolder => 'Раздел';

  String get vaultFolderName => 'Название раздела';

  String get vaultNewFolder => 'Новый раздел';

  String get vaultRenameFolder => 'Переименовать раздел';

  String get vaultDeleteFolder => 'Удалить раздел';

  String vaultDeleteFolderQuestion({required Object name}) =>
      'Удалить раздел «${name}» вместе с его папками? Все файлы и секреты останутся в корне сейфа.';

  String get vaultFolderActions => 'Действия с разделом';

  String get vaultAllEntries => 'Все';

  String get vaultUnfiled => 'Без раздела';

  String get vaultEmptyFolder => 'В этом разделе пока нет записей.';

  String get vaultFolderNameTaken => 'Такое название здесь уже используется.';

  String get vaultNameRequired => 'Введите название до 120 символов.';

  String get vaultRename => 'Переименовать сейф';

  String get vaultName => 'Название сейфа';

  String get vaultNameOptional => 'Название сейфа (необязательно)';

  String vaultDropHere({required Object name}) => 'Перетащите запись в «${name}»';

  String get vaultEntryHint => 'Нажмите, чтобы скопировать пароль · перетащите для переноса или сортировки';

  String get appName => 'SkySecret';

  String get windowsOnly => 'SkySecret работает в Windows.';

  String get clipboardBusy => 'Буфер обмена занят. Попробуйте ещё раз.';

  String get hide => 'Скрыть в трей · Esc';

  String get vault => 'Сейф';

  String get generator => 'Генератор';

  String get headline => 'Под рукой.\nТолько для вас.';

  String get subtitle => 'Одно место для паролей, заметок и файлов.';

  String get emptyVault => 'Сейф ещё не создан';

  String get vaultUnavailable => 'Хранилище пока недоступно.\nГенератор паролей уже работает.';

  String get openGenerator => 'Открыть генератор';

  String get newPassword => 'Новый пароль';

  String get generatedLocally => 'Создаётся на устройстве и не сохраняется.';

  String get length => 'Длина';

  String get symbols => 'Специальные символы';

  String get copied => 'Скопировано';

  String get copy => 'Копировать';

  String get regenerate => 'Другой пароль';

  String get clipboardHelp => 'Автоочистка через 30 секунд.\nБез истории Windows и облака.';

  String get githubDisconnected => 'GitHub не подключён';

  String get shortcutTitle => 'Горячая клавиша';

  String get shortcutHelp => 'Нажмите на поле и введите удобное сочетание.';

  String get unsupportedKey => 'Эта клавиша не поддерживается.';

  String get resetShortcut => 'Вернуть Shift + Space';

  String get cancel => 'Отмена';

  String get saving => 'Сохранение…';

  String get save => 'Сохранить';

  String get readSettingsFailed => 'Не удалось прочитать настройки. Используется Shift + Space.';

  String get trayFailed => 'Не удалось создать значок в трее. Перезапустите приложение.';

  String get exit => 'Выход';

  String get retry => 'Попробуйте ещё раз.';

  String get unsupportedShortcut => 'Это сочетание не поддерживается.';

  String get shortcutBusy => 'Сочетание занято Windows или другой программой.';

  String get saveSettingsFailed => 'Не удалось сохранить настройки. Прежнее сочетание оставлено.';

  String get trayUpdateFailed => 'Сочетание сохранено. Подпись в трее обновится после перезапуска.';

  String get shortcutFailed => 'Не удалось назначить сочетание. Попробуйте другое.';

  String openManager({required Object shortcut}) => 'Открыть менеджер    ${shortcut}';

  String shortcutUnavailable({required Object shortcut}) =>
      '${shortcut} недоступно. Откройте менеджер через значок в трее.';

  String shortcutTaken({required Object shortcut}) => '${shortcut} занято. Откройте менеджер через значок в трее.';

  String trayTooltip({required Object shortcut}) => 'SkySecret · ${shortcut}';

  String get shortcutPressKey => 'Теперь нажмите основную клавишу';

  String get shortcutListening => 'Ожидаю нажатие клавиш…';

  String get shortcutClickToRecord => 'Нажмите, чтобы изменить сочетание';

  String get vaultLocal => 'Локальный сейф';

  String get vaultLocked => 'Сейф заблокирован';

  String get vaultLock => 'Заблокировать сейф';

  String get vaultCreateHelp =>
      'Придумайте мастер-пароль, который запомните. Он нужен для открытия данных, сбросить его нельзя.';

  String get vaultUnlockHelp => 'Введите мастер-пароль, чтобы открыть сейф на этом устройстве.';

  String get vaultMasterPassword => 'Мастер-пароль';

  String get vaultConfirmPassword => 'Повторите мастер-пароль';

  String get vaultCreate => 'Создать сейф';

  String get vaultUnlock => 'Открыть';

  String get vaultWorking => 'Открываем сейф…';

  String get vaultEntryTitle => 'Название';

  String get vaultUsername => 'Логин';

  String get vaultEntryPassword => 'Пароль';

  String get vaultNotes => 'Заметки';

  String get vaultAddEntry => 'Добавить запись';

  String get vaultNoEntries => 'Сейф готов. Добавьте первую запись.';

  String get vaultLocalOnly => 'Данные зашифрованы на этом устройстве. Копия в GitHub пока не подключена.';

  String get vaultPasswordRequired => 'Введите мастер-пароль.';

  String get vaultMemoryProtectionFailed =>
      'Windows не смогла защитить память. Операция остановлена; сохранённый сейф не изменён. Закройте лишние приложения и повторите попытку.';

  String get windowPrivacyFailed => 'Windows не смогла включить защиту окна от захвата экрана.';

  String get vaultPasswordRequirements =>
      'Не менее 16 символов. Подходит длинная уникальная парольная фраза; заглавные буквы, цифры и спецсимволы необязательны. Очевидные пароли и повторяющиеся шаблоны не принимаются.';

  String get vaultPasswordMismatch => 'Пароли не совпадают.';

  String get vaultUnlockFailed => 'Неверный пароль или повреждённый сейф.';

  String get vaultFormatFailed => 'Сейф повреждён или его формат не поддерживается.';

  String get vaultConflict => 'Сейф изменился на диске. Заблокируйте и откройте его заново перед сохранением.';

  String get vaultTitleRequired => 'Введите название.';

  String get vaultLimit => 'Размер записи или сейфа превышает допустимый.';

  String get vaultReadFailed => 'Не удалось получить доступ к сейфу. Проверьте доступ к локальным данным приложения.';

  String get vaultWriteFailed => 'Не удалось завершить операцию. Проверьте свободное место и доступ к файлу.';

  String get vaultPreferencesSaveFailed => 'Не удалось сохранить настройки. Изменение не применено.';

  String get vaultSettings => 'Настройки сейфов';

  String get vaultAutoLock => 'Автоблокировка';

  String get vaultLockWhenHidden => 'Блокировать при скрытии';

  String get vaultLockWhenHiddenHelp =>
      'Esc, крестик, сворачивание и уход в трей при потере фокуса блокируют сейф и закрывают редакторы. Несохранённые изменения теряются. Можно отключить отдельно от таймера.';

  String get vaultSnapshotCleanupWarning =>
      'Текущий сейф использует новый пароль, но часть локальных снимков не удалось удалить: они могут открываться старым паролем. Закройте программы, использующие эти файлы, и откройте сейф снова для повторной очистки. Внешние экспорты и история GitHub остаются отдельно.';

  String get vaultPasswordBackupWarning =>
      'После сохранения нового пароля локальная история восстановления и кэш синхронизации удаляются. Прежние экспорты и версии в GitHub по-прежнему открываются старым паролем. Если он скомпрометирован, проверьте новую независимую копию и замените репозиторий резервных копий; старые репозитории и скачанные копии автоматически не отзываются. Смените также раскрытые пароли учётных записей. Новые сейфы и смена пароля используют формат v2; обновите все устройства до SkySecret 0.2.0 или новее.';

  String get vaultAutoLockHelp => 'Через 2 минуты бездействия. Блокировка Windows и сон всегда блокируют сейф.';

  String get vaultPreferencesReadFailed => 'Не удалось прочитать настройки. Автоблокировка включена.';

  String get vaultAttachmentSaved => 'Файл сохранён на диск без шифрования.';

  String get vaultExport => 'Экспорт сейфа';

  String get vaultAddAttachment => 'Прикрепить файл';

  String get vaultSaveAttachment => 'Сохранить файл на диск';

  String get vaultNewPassword => 'Новый мастер-пароль';

  String get vaultChangePassword => 'Мастер-пароль';

  String get vaultInvalidFilename => 'Имя файла не поддерживается Windows. Переименуйте исходный файл.';

  String get vaultAttachmentHelp =>
      'До 20 МиБ на файл, до 50 МиБ всего. Изменения применяются кнопкой «Сохранить». Извлечённые файлы не зашифрованы.';

  String get vaultImportHelp =>
      'Введите пароль резервной копии. Она будет добавлена как отдельный сейф; существующие данные сохранятся.';

  String get vaultImportDone => 'Сейф проверен и импортирован.';

  String get vaultCurrentPassword => 'Текущий мастер-пароль';

  String get vaultDestinationExists =>
      'Файл уже существует или сейф изменился. Выберите новое имя файла; при смене пароля откройте сейф заново.';

  String get vaultAttachments => 'Файлы';

  String get vaultPasswordChanged => 'Мастер-пароль изменён. Создайте новую резервную копию.';

  String get vaultExportDone => 'Зашифрованная копия сохранена со всеми вложениями.';

  String get vaultSystemLockFailed => 'Не удалось подключить блокировку по событиям Windows. Перезапустите приложение.';

  String get vaultImport => 'Импорт сейфа';

  String get vaultAllFiles => 'Все файлы';

  String get vaultDeleteVault => 'Удалить сейф';

  String vaultDeleteVaultQuestion({required Object name}) =>
      'Удалить сейф «${name}» с этого компьютера? Все его записи и файлы будут удалены без возможности отмены. Другие сейфы и экспортированные резервные копии сохранятся.';

  String get vaultDeleted => 'Сейф удалён с этого компьютера.';

  String get vaultAttachmentLimit => 'Лимит: 20 МиБ на файл, 50 МиБ всего.';

  String get vaultChangePasswordHelp =>
      'Задайте новый пароль. Старые резервные копии останутся доступны по прежнему паролю.';

  String get fileEditorSaveFailed =>
      'Не удалось сохранить. Сейф занят, файл изменён или превышен лимит 2 МиБ. Повторите попытку; при конфликте откройте файл заново.';

  String get vaultDeleteFile => 'Удалить файл';

  String get fileEditorShortcut => 'Ctrl+S · сохранить в сейф';

  String get fileEditorUnsupported =>
      'Просмотр недоступен для этого формата, кодировки или файла больше 2 МиБ. Сохраните исходный файл на компьютер.';

  String get vaultAddFile => 'Добавить файл';

  String get fileEditorStored => 'Сохранено в зашифрованном сейфе';

  String get vaultFileHint => 'Открыть файл · перетащить для переноса или сортировки';

  String get fileEditorModified => 'Есть несохранённые изменения';

  String get fileEditorCloseHelp => 'Обновлённый файл будет сохранён в зашифрованном сейфе.';

  String get fileEditorUnsaved => 'Сохранить изменения?';

  String get fileEditorDiscard => 'Не сохранять';

  String get vaultDropLocked => 'Сначала откройте сейф мастер-паролем, затем перенесите файлы ещё раз.';

  String vaultFilesAdded({required Object count}) => 'Добавлено файлов: ${count}';

  String get vaultDropHint => 'Перетащите файлы на раздел или папку, либо отпустите в корне сейфа.';

  String get vaultDropTitle => 'Файлы в сейф';

  String get vaultDropBusy => 'Завершите текущее действие и перенесите файлы ещё раз.';

  String get vaultDropFilesOnly => 'Переносите отдельные файлы. Папки и ссылки не поддерживаются. Ничего не добавлено.';

  String get vaultDropChanged => 'Один из файлов изменился во время чтения. Повторите перенос. Ничего не добавлено.';

  String get vaultDropReadFailed => 'Не удалось получить файлы. Повторите перенос или используйте «Добавить файл».';

  String get vaultDropUnavailable =>
      'Перетаскивание файлов недоступно. Перезапустите приложение или используйте «Добавить файл».';

  String get githubTitle => 'Резервные копии GitHub';

  String get githubReady => 'GitHub · готов';

  String get githubPaused => 'GitHub · вручную';

  String get githubWorking => 'GitHub · выполняется…';

  String get githubSynced => 'GitHub · проверено';

  String get githubConflict => 'GitHub · конфликт';

  String get githubFailed => 'GitHub · нужна проверка';

  String get githubNetworkError =>
      'GitHub недоступен. Данные сохранены локально; отправка будет повторена после восстановления сети.';

  String get githubAuthError => 'Токен истёк или отозван. Создайте новый для того же репозитория и замените его здесь.';

  String get githubAccessError => 'GitHub ограничил запросы или отказал в доступе. Проверьте права и повторите позже.';

  String get githubMissingError =>
      'Подключённый репозиторий недоступен. Проверьте доступ в GitHub; новая замена не создаётся.';

  String get githubConflictHelp =>
      'Удалённая версия изменилась. Автоматическая отправка остановлена. Можно сохранить локальные сейфы как новые копии, сохранив обе версии, или восстановить удалённую копию отдельным сейфом.';

  String get githubRepositoryChangedError =>
      'Выбран другой репозиторий: у приложения сохранена привязка к прежним копиям. Укажите прежний репозиторий. Если вы удалили его и создали заново с тем же именем, GitHub считает его новым. Локальные сейфы не изменены.';

  String get githubRepositorySetupError =>
      'В новом репозитории найдены файлы помимо README.md. Для первого подключения создайте отдельный приватный репозиторий только с README.md. Если здесь уже есть копии SkySecret, снимите флажок нового репозитория. Ничего не удаляйте из существующих копий.';

  String get githubFormatError =>
      'Структура резервной копии не поддерживается или повреждена. Рабочие сейфы не изменены.';

  String get githubStorageError =>
      'Не удалось прочитать или сохранить защищённые настройки GitHub. Отправка остановлена; проверьте доступ к локальному хранилищу.';

  String get githubIdentityError =>
      'Нужен токен прежнего владельца. Автоматический перенос сейфов в другой аккаунт запрещён.';

  String get githubConfigurationError =>
      'Укажите fine-grained token (github_pat_…) и полный адрес https://github.com/владелец/репозиторий или владелец/репозиторий. Одного https://github.com недостаточно.';

  String get githubBrowserError => 'Не удалось открыть браузер. Откройте GitHub вручную; ссылки есть в руководстве.';

  String get githubFindBackups => 'Обновить список копий';

  String get githubCreateRepository => 'Создать репозиторий на GitHub';

  String get githubAutoBackup => 'Автоматическое резервирование';

  String get githubAutoBackupHelp =>
      'Обычные резервные копии отправляются через 5 секунд после сохранения; при сбое сети повторяем через 30 минут. Сейфы, для которых включена синхронизация, получают и отправляют изменения только по кнопке «Синхронизировать» внизу главного окна. Фонового опроса нет. Удаление целого локального сейфа не удаляет копию GitHub.';

  String get githubBackupNow => 'Сохранить копию сейчас';

  String githubLastBackup({required Object date, required Object time}) => 'Проверено: ${date}, ${time}';

  String get githubKeepBoth => 'Сохранить обе версии';

  String get githubRestore => 'Восстановить сейф';

  String get githubRestoreHelp =>
      'Нужен мастер-пароль выбранной копии. Для работы на нескольких устройствах оставьте привязку включённой. Для независимой копии выключите её. Существующие сейфы не заменяются. Названия зашифрованы, поэтому до открытия видны идентификаторы.';

  String get githubNoBackups => 'Резервных копий пока нет.';

  String get githubRestoreError => 'Не удалось восстановить сейф. Проверьте мастер-пароль и целостность копии.';

  String get githubHistoryHelp =>
      'История GitHub хранит старые зашифрованные версии: смена мастер-пароля их не отзывает. Отключение удаляет токен с этого устройства; для отзыва удалите его в GitHub → Settings → Developer settings → Personal access tokens.';

  String get githubDisconnect => 'Отключить GitHub';

  String get githubClose => 'Закрыть';

  String get githubPending => 'GitHub · ожидает отправки';

  String get githubSetupHelp =>
      'GitHub хранит зашифрованные копии ваших сейфов. Настройте подключение один раз по шагам ниже. Регистрация OAuth App или GitHub App не нужна.';

  String get githubSetupRepositoryStep => '1. Место для копий';

  String get githubSetupRepositoryHelp =>
      'На GitHub выберите свой личный аккаунт, задайте имя репозитория, выберите Private и включите Add a README file. Не добавляйте .gitignore или лицензию. Если репозиторий с копиями уже есть, используйте его.';

  String get githubSetupTokenStep => '2. Ключ доступа';

  String get githubSetupTokenHelp =>
      'Кнопка ниже открывает создание fine-grained token. Resource owner — ваш аккаунт. Repository access → Only select repositories → только репозиторий копий. Contents → Read and write; Metadata → Read-only. Остальные права не добавляйте. Выберите срок действия, нажмите Generate token и скопируйте github_pat_… в поле ниже.';

  String get githubSetupGuide => 'Открыть подробную инструкцию';

  String get githubSetupConnectStep => '3. Подключение';

  String get githubSetupConnectHelp =>
      'Вставьте полный адрес репозитория и токен. Подтвердите выбранные права; для нового репозитория с README отметьте подготовку. Нажмите «Подключить» — сохранённые сейфы будут отправлены автоматически. Дождитесь завершения без ошибки.';

  String get githubManageTokens => 'Управлять токенами на GitHub';

  String get githubCreateToken => 'Создать токен GitHub';

  String get githubRepositoryAddress => 'Ссылка на репозиторий';

  String get githubToken => 'Fine-grained token';

  String get githubTokenHelp => 'Хранится под защитой Windows DPAPI и отправляется только GitHub.';

  String get githubTokenConfirmation =>
      'В настройках токена выбран только этот репозиторий; из прав добавлено только Contents → Read and write.';

  String get githubInitializeRepository => 'Это новый репозиторий только с README — подготовить его для копий.';

  String get githubConnect => 'Подключить';

  String get githubReplaceToken => 'Заменить токен';

  String get syncNow => 'Синхронизировать';

  String get syncWorking => 'Обмен с GitHub…';

  String get syncDone =>
      'Открытый сейф синхронизирован с проверенной версией GitHub. На другом устройстве нажмите «Синхронизировать», чтобы получить изменения.';

  String syncConflicts({required Object count}) =>
      'Сейф синхронизирован. Конфликтов: ${count}. Варианты записей помечены и сохранены. Откройте меню сейфа → Разобрать конфликты, затем синхронизируйте результат.';

  String get syncFinishEditing =>
      'Сначала сохраните или отмените правки и закройте редакторы файлов. Затем синхронизируйте сейф.';

  String get syncUnlock =>
      'Откройте нужный сейф мастер-паролем. На новом устройстве выберите копию GitHub и включите привязку для синхронизации.';

  String get syncKeyChanged =>
      'Копия использует другой ключ. Автоматическое объединение отключено: локальные записи не будут зашифрованы ключом этой копии. Текущий сейф сохранён. Можно восстановить удалённую версию отдельным сейфом и проверить её. При раскрытии прежнего пароля подключите локальный сейф к новому репозиторию.';

  String get syncLink => 'Привязать к этой копии для ручной синхронизации между устройствами';

  String get syncAlreadyLinked =>
      'Эта копия уже подключена на этом компьютере. Откройте выбранный сейф и нажмите «Синхронизировать».';

  String get syncVaultHelp =>
      'Кнопка «Синхронизировать» получает и отправляет изменения открытого сейфа. После первой синхронизации этот сейф обменивается данными только по кнопке. Фонового опроса нет.';

  String get syncRollback =>
      'Обнаружена старая версия или несовместимая история. Синхронизация остановлена, локальные данные сохранены. Проверьте другие устройства и историю сейфа.';

  String get vaultHistory => 'История и восстановление';

  String get vaultHistoryHelp =>
      'Выберите зашифрованный снимок. Восстановление создаёт отдельный сейф и требует пароль того времени. Храним до 20 предыдущих состояний на сейф в пределах 256 МиБ.';

  String get vaultHistoryEmpty => 'Предыдущих состояний пока нет.';

  String get syncReviewConflicts => 'Разобрать конфликты';

  String get syncReviewHelp =>
      'Раскройте варианты для сравнения. Выбор оставит один вариант, остальные останутся в локальной истории. Файлы можно открыть из списка сейфа.';

  String get syncNoConflicts => 'Неразобранных конфликтов записей нет.';

  String syncVariant({required Object id}) => 'Вариант ${id}';

  String get syncKeepVariant => 'Оставить этот вариант';

  String get syncKeepVariantQuestion =>
      'Оставить выбранный вариант? Другие варианты этой группы будут удалены из текущего сейфа. Предыдущее состояние останется в локальной истории.';

  String get syncRelink => 'Связать с открытым сейфом';

  String get syncRelinkHelp =>
      'Восстановить связь открытого сейфа с этой копией? Приложение проверит принадлежность и историю. При несовместимой истории связь не будет изменена. Данные отправятся только после нажатия «Синхронизировать».';

  String get syncRelinkDone => 'Связь восстановлена. Нажмите «Синхронизировать» для обмена изменениями.';

  String get githubRecoverConnection => 'Восстановить подключение';

  String get githubRecoverConnectionHelp =>
      'Журнал подключения повреждён. Сбросить подключение и ввести токен заново? Локальные сейфы и история останутся. Все существующие сейфы перейдут в ручной режим; связь с копиями нужно восстановить кнопкой цепочки рядом с копией.';

  String get syncLocalConfirmed => 'Открытый сейф соответствует последнему подтверждённому обмену.';

  String get syncLocalPending => 'В открытом сейфе есть неподтверждённые изменения.';

  String syncVaultChecked({required Object date}) => 'Этот сейф: ${date}';

  String get syncManualOnly => 'Обмен только по кнопке. Изменения на других устройствах без нажатия не проверяются.';

  String get syncShowPassword => 'Показать или скрыть пароль';

  String get sshAdd => 'Создать SSH-подключение';

  String get sshConnect => 'Подключиться по SSH';

  String get sshHost => 'Адрес сервера (DNS или IP)';

  String get sshPort => 'Порт';

  String get sshHelp =>
      'Пароль передаётся один раз, по запросу OpenSSH. Доступ к паролю прекращается при блокировке сейфа или через 2 минуты после запуска. Во время входа менеджер не скрывается автоматически. Открытый терминал продолжает работать после блокировки.';

  String get sshHostKeyTitle => 'Ключ SSH-сервера';

  String get sshHostKeyHelp =>
      'Сверьте отпечаток ключа с владельцем сервера по независимому каналу. Подтверждайте только знакомый сервер. OpenSSH сохранит ключ в known_hosts.';

  String get sshTrustHost => 'Доверять этому ключу';

  String get sshStarted => 'Терминал SSH запущен. При первом подключении подтвердите ключ сервера в SkySecret.';

  String get sshClosed => 'SSH-терминал закрыт.';

  String get sshFailed =>
      'SSH завершился с ошибкой или запуск не удался. Проверьте адрес, доступность сервера, пароль и ключ сервера.';

  String get sshMissing => 'Не найден Windows OpenSSH Client. Установите его в дополнительных компонентах Windows.';

  String get sshActive => 'Для этой записи уже открыт SSH-терминал. Закройте его перед повторным подключением.';

  String get sshLimit => 'Одновременно можно открыть до 8 SSH-терминалов.';

  String get sshInvalid =>
      'Укажите DNS-имя или IP без команды, порт 1–65535 и пользователя латиницей (буквы, цифры, _, ., -, допустим символ доллара в конце). Пароль обязателен: до 1000 байт UTF-8, без переноса строк и NUL.';

  String get captureVisible => 'Показывать при записи экрана';

  String get captureVisibleHelp =>
      'Включите, чтобы менеджер и текстовые редакторы были видны на скриншотах, в записи и демонстрации экрана. Содержимое окон может попасть в запись. По умолчанию выключено.';

  String get captureSettingFailed =>
      'Не удалось применить настройку захвата ко всем окнам. Проверьте их видимость в программе записи.';

  String get syncKeyChangedTitle => 'Ключ копии изменился';

  String get syncKeepLocal => 'Оставить локальный сейф';

  String get syncOpenRemoteCopy => 'Восстановить отдельно';

  String get browserAll => 'Все';

  String get browserFavorites => 'Избранное';

  String browserTrash({required Object count}) => 'Корзина (${count})';

  String get browserSearch => 'Поиск';

  String get browserSearchHint => 'Название, логин, сервер или папка';

  String get browserCloseSearch => 'Закрыть поиск';

  String get browserTrashHelp =>
      'Удалённые записи остаются здесь в зашифрованном виде до окончательного удаления и учитываются в лимитах сейфа. В прежних резервных копиях они могут сохраниться.';

  String get browserEmptyTrash => 'Очистить корзину';

  String get browserNoResults => 'Подходящих записей нет';

  String get browserNoFavorites => 'Отметьте запись звездой, чтобы находить её здесь.';

  String get browserTrashEmpty => 'Корзина пуста';

  String get browserFavorite => 'В избранное';

  String get browserUnfavorite => 'Убрать из избранного';

  String get browserRestore => 'Восстановить';

  String get browserDeleteForever => 'Удалить окончательно';

  String browserDeleteForeverHelp({required Object name}) =>
      'Окончательно удалить «${name}» из этого сейфа? Отменить это действие здесь нельзя. В прежних резервных копиях и истории восстановления запись может сохраниться.';

  String browserEmptyTrashHelp({required Object count}) =>
      'Окончательно удалить записи из корзины: ${count}? Отменить это действие здесь нельзя. В прежних резервных копиях и истории восстановления записи могут сохраниться.';

  String get browserMovedToTrash => 'Перемещено в зашифрованную корзину';

  String get browserUndo => 'Отменить';

  String get browserRestored => 'Запись восстановлена';

  String get searchKeyboardHelp => '↑ ↓ Выбрать   ·   Enter Открыть / скопировать   ·   Esc Закрыть';

  String get searchCopyPassword => 'Скопировать пароль';

  String get searchUnavailable => 'Не удалось открыть поиск. Попробуйте ещё раз.';

  String get searchRefine => 'Первые 50 совпадений. Уточните запрос.';

  String get searchStartTyping => 'Начните вводить название или логин';

  String get searchOpenFile => 'Открыть файл';
}

extension on Translations {
  dynamic _flatMapFunction(String path) {
    return switch (path) {
      'vaultCreateTextFile' => 'Создать .txt',
      'vaultCreateText' => 'Создать',
      'vaultTextFileName' => 'Имя файла',
      'vaultTextDefaultName' => 'Новый документ',
      'vaultTextNameInvalid' => 'Введите допустимое имя файла. Расширение .txt добавится автоматически.',
      'vaultTextNameTaken' => 'Здесь уже есть файл с таким именем. Выберите другое.',
      'vaultSecretKind' => 'Секрет',
      'vaultRoot' => 'Без раздела',
      'vaultContents' => 'Содержимое',
      'vaultLocation' => 'Расположение',
      'vaultLocationActions' => 'Действия',
      'vaultNewSubfolder' => 'Создать папку',
      'vaultRenameSubfolder' => 'Переименовать папку',
      'vaultSubfolderName' => 'Название папки',
      'vaultDeleteSubfolder' => 'Удалить папку',
      'vaultDeleteSubfolderQuestion' => ({
        required Object name,
      }) => 'Удалить папку «${name}»? Все её файлы и секреты останутся в разделе.',
      'vaultRootDropHint' => 'Добавляйте файлы и секреты прямо сюда или создайте свой раздел.',
      'vaultFolderDropHint' => 'Перетащите сюда файлы или секреты. Добавление также доступно в меню.',
      'vaultMoveToRoot' => 'Переместить в корень сейфа',
      'vaultChoose' => 'Выбрать сейф',
      'vaultGeneral' => 'Общее',
      'vaultPasswordOptions' => 'Настройки пароля',
      'vaultPasswordLength' => ({required Object length}) => 'Пароль · ${length} симв.',
      'vaultGeneratePassword' => 'Сгенерировать',
      'vaultNew' => 'Создать ещё один сейф',
      'vaultPrimary' => 'Основной сейф',
      'vaultIdentifier' => ({required Object id}) => 'Сейф · ${id}',
      'vaultDelete' => 'Удалить',
      'vaultDeleteEntry' => 'Удалить запись',
      'vaultDeleteEntryQuestion' => ({required Object name}) => 'Удалить «${name}»? Это действие нельзя отменить.',
      'vaultEditEntry' => 'Редактировать запись',
      'vaultFolders' => 'Разделы',
      'vaultFolder' => 'Раздел',
      'vaultFolderName' => 'Название раздела',
      'vaultNewFolder' => 'Новый раздел',
      'vaultRenameFolder' => 'Переименовать раздел',
      'vaultDeleteFolder' => 'Удалить раздел',
      'vaultDeleteFolderQuestion' => ({
        required Object name,
      }) => 'Удалить раздел «${name}» вместе с его папками? Все файлы и секреты останутся в корне сейфа.',
      'vaultFolderActions' => 'Действия с разделом',
      'vaultAllEntries' => 'Все',
      'vaultUnfiled' => 'Без раздела',
      'vaultEmptyFolder' => 'В этом разделе пока нет записей.',
      'vaultFolderNameTaken' => 'Такое название здесь уже используется.',
      'vaultNameRequired' => 'Введите название до 120 символов.',
      'vaultRename' => 'Переименовать сейф',
      'vaultName' => 'Название сейфа',
      'vaultNameOptional' => 'Название сейфа (необязательно)',
      'vaultDropHere' => ({required Object name}) => 'Перетащите запись в «${name}»',
      'vaultEntryHint' => 'Нажмите, чтобы скопировать пароль · перетащите для переноса или сортировки',
      'appName' => 'SkySecret',
      'windowsOnly' => 'SkySecret работает в Windows.',
      'clipboardBusy' => 'Буфер обмена занят. Попробуйте ещё раз.',
      'hide' => 'Скрыть в трей · Esc',
      'vault' => 'Сейф',
      'generator' => 'Генератор',
      'headline' => 'Под рукой.\nТолько для вас.',
      'subtitle' => 'Одно место для паролей, заметок и файлов.',
      'emptyVault' => 'Сейф ещё не создан',
      'vaultUnavailable' => 'Хранилище пока недоступно.\nГенератор паролей уже работает.',
      'openGenerator' => 'Открыть генератор',
      'newPassword' => 'Новый пароль',
      'generatedLocally' => 'Создаётся на устройстве и не сохраняется.',
      'length' => 'Длина',
      'symbols' => 'Специальные символы',
      'copied' => 'Скопировано',
      'copy' => 'Копировать',
      'regenerate' => 'Другой пароль',
      'clipboardHelp' => 'Автоочистка через 30 секунд.\nБез истории Windows и облака.',
      'githubDisconnected' => 'GitHub не подключён',
      'shortcutTitle' => 'Горячая клавиша',
      'shortcutHelp' => 'Нажмите на поле и введите удобное сочетание.',
      'unsupportedKey' => 'Эта клавиша не поддерживается.',
      'resetShortcut' => 'Вернуть Shift + Space',
      'cancel' => 'Отмена',
      'saving' => 'Сохранение…',
      'save' => 'Сохранить',
      'readSettingsFailed' => 'Не удалось прочитать настройки. Используется Shift + Space.',
      'trayFailed' => 'Не удалось создать значок в трее. Перезапустите приложение.',
      'exit' => 'Выход',
      'retry' => 'Попробуйте ещё раз.',
      'unsupportedShortcut' => 'Это сочетание не поддерживается.',
      'shortcutBusy' => 'Сочетание занято Windows или другой программой.',
      'saveSettingsFailed' => 'Не удалось сохранить настройки. Прежнее сочетание оставлено.',
      'trayUpdateFailed' => 'Сочетание сохранено. Подпись в трее обновится после перезапуска.',
      'shortcutFailed' => 'Не удалось назначить сочетание. Попробуйте другое.',
      'openManager' => ({required Object shortcut}) => 'Открыть менеджер    ${shortcut}',
      'shortcutUnavailable' => ({
        required Object shortcut,
      }) => '${shortcut} недоступно. Откройте менеджер через значок в трее.',
      'shortcutTaken' => ({required Object shortcut}) => '${shortcut} занято. Откройте менеджер через значок в трее.',
      'trayTooltip' => ({required Object shortcut}) => 'SkySecret · ${shortcut}',
      'shortcutPressKey' => 'Теперь нажмите основную клавишу',
      'shortcutListening' => 'Ожидаю нажатие клавиш…',
      'shortcutClickToRecord' => 'Нажмите, чтобы изменить сочетание',
      'vaultLocal' => 'Локальный сейф',
      'vaultLocked' => 'Сейф заблокирован',
      'vaultLock' => 'Заблокировать сейф',
      'vaultCreateHelp' =>
        'Придумайте мастер-пароль, который запомните. Он нужен для открытия данных, сбросить его нельзя.',
      'vaultUnlockHelp' => 'Введите мастер-пароль, чтобы открыть сейф на этом устройстве.',
      'vaultMasterPassword' => 'Мастер-пароль',
      'vaultConfirmPassword' => 'Повторите мастер-пароль',
      'vaultCreate' => 'Создать сейф',
      'vaultUnlock' => 'Открыть',
      'vaultWorking' => 'Открываем сейф…',
      'vaultEntryTitle' => 'Название',
      'vaultUsername' => 'Логин',
      'vaultEntryPassword' => 'Пароль',
      'vaultNotes' => 'Заметки',
      'vaultAddEntry' => 'Добавить запись',
      'vaultNoEntries' => 'Сейф готов. Добавьте первую запись.',
      'vaultLocalOnly' => 'Данные зашифрованы на этом устройстве. Копия в GitHub пока не подключена.',
      'vaultPasswordRequired' => 'Введите мастер-пароль.',
      'vaultMemoryProtectionFailed' => 'Windows не смогла защитить память. Операция остановлена; сохранённый сейф не изменён. Закройте лишние приложения и повторите попытку.',
      'windowPrivacyFailed' => 'Windows не смогла включить защиту окна от захвата экрана.',
      'vaultPasswordRequirements' => 'Не менее 16 символов. Подходит длинная уникальная парольная фраза; заглавные буквы, цифры и спецсимволы необязательны. Очевидные пароли и повторяющиеся шаблоны не принимаются.',
      'vaultPasswordMismatch' => 'Пароли не совпадают.',
      'vaultUnlockFailed' => 'Неверный пароль или повреждённый сейф.',
      'vaultFormatFailed' => 'Сейф повреждён или его формат не поддерживается.',
      'vaultConflict' => 'Сейф изменился на диске. Заблокируйте и откройте его заново перед сохранением.',
      'vaultTitleRequired' => 'Введите название.',
      'vaultLimit' => 'Размер записи или сейфа превышает допустимый.',
      'vaultReadFailed' => 'Не удалось получить доступ к сейфу. Проверьте доступ к локальным данным приложения.',
      'vaultWriteFailed' => 'Не удалось завершить операцию. Проверьте свободное место и доступ к файлу.',
      'vaultPreferencesSaveFailed' => 'Не удалось сохранить настройки. Изменение не применено.',
      'vaultSettings' => 'Настройки сейфов',
      'vaultAutoLock' => 'Автоблокировка',
      'vaultLockWhenHidden' => 'Блокировать при скрытии',
      'vaultLockWhenHiddenHelp' => 'Esc, крестик, сворачивание и уход в трей при потере фокуса блокируют сейф и закрывают редакторы. Несохранённые изменения теряются. Можно отключить отдельно от таймера.',
      'vaultSnapshotCleanupWarning' => 'Текущий сейф использует новый пароль, но часть локальных снимков не удалось удалить: они могут открываться старым паролем. Закройте программы, использующие эти файлы, и откройте сейф снова для повторной очистки. Внешние экспорты и история GitHub остаются отдельно.',
      'vaultPasswordBackupWarning' => 'После сохранения нового пароля локальная история восстановления и кэш синхронизации удаляются. Прежние экспорты и версии в GitHub по-прежнему открываются старым паролем. Если он скомпрометирован, проверьте новую независимую копию и замените репозиторий резервных копий; старые репозитории и скачанные копии автоматически не отзываются. Смените также раскрытые пароли учётных записей. Новые сейфы и смена пароля используют формат v2; обновите все устройства до SkySecret 0.2.0 или новее.',
      'vaultAutoLockHelp' => 'Через 2 минуты бездействия. Блокировка Windows и сон всегда блокируют сейф.',
      'vaultPreferencesReadFailed' => 'Не удалось прочитать настройки. Автоблокировка включена.',
      'vaultAttachmentSaved' => 'Файл сохранён на диск без шифрования.',
      'vaultExport' => 'Экспорт сейфа',
      'vaultAddAttachment' => 'Прикрепить файл',
      'vaultSaveAttachment' => 'Сохранить файл на диск',
      'vaultNewPassword' => 'Новый мастер-пароль',
      'vaultChangePassword' => 'Мастер-пароль',
      'vaultInvalidFilename' => 'Имя файла не поддерживается Windows. Переименуйте исходный файл.',
      'vaultAttachmentHelp' => 'До 20 МиБ на файл, до 50 МиБ всего. Изменения применяются кнопкой «Сохранить». Извлечённые файлы не зашифрованы.',
      'vaultImportHelp' =>
        'Введите пароль резервной копии. Она будет добавлена как отдельный сейф; существующие данные сохранятся.',
      'vaultImportDone' => 'Сейф проверен и импортирован.',
      'vaultCurrentPassword' => 'Текущий мастер-пароль',
      'vaultDestinationExists' =>
        'Файл уже существует или сейф изменился. Выберите новое имя файла; при смене пароля откройте сейф заново.',
      'vaultAttachments' => 'Файлы',
      'vaultPasswordChanged' => 'Мастер-пароль изменён. Создайте новую резервную копию.',
      'vaultExportDone' => 'Зашифрованная копия сохранена со всеми вложениями.',
      'vaultSystemLockFailed' => 'Не удалось подключить блокировку по событиям Windows. Перезапустите приложение.',
      'vaultImport' => 'Импорт сейфа',
      'vaultAllFiles' => 'Все файлы',
      'vaultDeleteVault' => 'Удалить сейф',
      'vaultDeleteVaultQuestion' => ({
        required Object name,
      }) => 'Удалить сейф «${name}» с этого компьютера? Все его записи и файлы будут удалены без возможности отмены. Другие сейфы и экспортированные резервные копии сохранятся.',
      'vaultDeleted' => 'Сейф удалён с этого компьютера.',
      'vaultAttachmentLimit' => 'Лимит: 20 МиБ на файл, 50 МиБ всего.',
      'vaultChangePasswordHelp' =>
        'Задайте новый пароль. Старые резервные копии останутся доступны по прежнему паролю.',
      'fileEditorSaveFailed' => 'Не удалось сохранить. Сейф занят, файл изменён или превышен лимит 2 МиБ. Повторите попытку; при конфликте откройте файл заново.',
      'vaultDeleteFile' => 'Удалить файл',
      'fileEditorShortcut' => 'Ctrl+S · сохранить в сейф',
      'fileEditorUnsupported' => 'Просмотр недоступен для этого формата, кодировки или файла больше 2 МиБ. Сохраните исходный файл на компьютер.',
      'vaultAddFile' => 'Добавить файл',
      'fileEditorStored' => 'Сохранено в зашифрованном сейфе',
      'vaultFileHint' => 'Открыть файл · перетащить для переноса или сортировки',
      'fileEditorModified' => 'Есть несохранённые изменения',
      'fileEditorCloseHelp' => 'Обновлённый файл будет сохранён в зашифрованном сейфе.',
      'fileEditorUnsaved' => 'Сохранить изменения?',
      'fileEditorDiscard' => 'Не сохранять',
      'vaultDropLocked' => 'Сначала откройте сейф мастер-паролем, затем перенесите файлы ещё раз.',
      'vaultFilesAdded' => ({required Object count}) => 'Добавлено файлов: ${count}',
      'vaultDropHint' => 'Перетащите файлы на раздел или папку, либо отпустите в корне сейфа.',
      'vaultDropTitle' => 'Файлы в сейф',
      'vaultDropBusy' => 'Завершите текущее действие и перенесите файлы ещё раз.',
      'vaultDropFilesOnly' => 'Переносите отдельные файлы. Папки и ссылки не поддерживаются. Ничего не добавлено.',
      'vaultDropChanged' => 'Один из файлов изменился во время чтения. Повторите перенос. Ничего не добавлено.',
      'vaultDropReadFailed' => 'Не удалось получить файлы. Повторите перенос или используйте «Добавить файл».',
      'vaultDropUnavailable' =>
        'Перетаскивание файлов недоступно. Перезапустите приложение или используйте «Добавить файл».',
      'githubTitle' => 'Резервные копии GitHub',
      'githubReady' => 'GitHub · готов',
      'githubPaused' => 'GitHub · вручную',
      'githubWorking' => 'GitHub · выполняется…',
      'githubSynced' => 'GitHub · проверено',
      'githubConflict' => 'GitHub · конфликт',
      'githubFailed' => 'GitHub · нужна проверка',
      'githubNetworkError' =>
        'GitHub недоступен. Данные сохранены локально; отправка будет повторена после восстановления сети.',
      'githubAuthError' => 'Токен истёк или отозван. Создайте новый для того же репозитория и замените его здесь.',
      'githubAccessError' => 'GitHub ограничил запросы или отказал в доступе. Проверьте права и повторите позже.',
      'githubMissingError' =>
        'Подключённый репозиторий недоступен. Проверьте доступ в GitHub; новая замена не создаётся.',
      'githubConflictHelp' => 'Удалённая версия изменилась. Автоматическая отправка остановлена. Можно сохранить локальные сейфы как новые копии, сохранив обе версии, или восстановить удалённую копию отдельным сейфом.',
      'githubRepositoryChangedError' => 'Выбран другой репозиторий: у приложения сохранена привязка к прежним копиям. Укажите прежний репозиторий. Если вы удалили его и создали заново с тем же именем, GitHub считает его новым. Локальные сейфы не изменены.',
      'githubRepositorySetupError' => 'В новом репозитории найдены файлы помимо README.md. Для первого подключения создайте отдельный приватный репозиторий только с README.md. Если здесь уже есть копии SkySecret, снимите флажок нового репозитория. Ничего не удаляйте из существующих копий.',
      'githubFormatError' => 'Структура резервной копии не поддерживается или повреждена. Рабочие сейфы не изменены.',
      'githubStorageError' => 'Не удалось прочитать или сохранить защищённые настройки GitHub. Отправка остановлена; проверьте доступ к локальному хранилищу.',
      'githubIdentityError' =>
        'Нужен токен прежнего владельца. Автоматический перенос сейфов в другой аккаунт запрещён.',
      'githubConfigurationError' => 'Укажите fine-grained token (github_pat_…) и полный адрес https://github.com/владелец/репозиторий или владелец/репозиторий. Одного https://github.com недостаточно.',
      'githubBrowserError' => 'Не удалось открыть браузер. Откройте GitHub вручную; ссылки есть в руководстве.',
      'githubFindBackups' => 'Обновить список копий',
      'githubCreateRepository' => 'Создать репозиторий на GitHub',
      'githubAutoBackup' => 'Автоматическое резервирование',
      'githubAutoBackupHelp' => 'Обычные резервные копии отправляются через 5 секунд после сохранения; при сбое сети повторяем через 30 минут. Сейфы, для которых включена синхронизация, получают и отправляют изменения только по кнопке «Синхронизировать» внизу главного окна. Фонового опроса нет. Удаление целого локального сейфа не удаляет копию GitHub.',
      'githubBackupNow' => 'Сохранить копию сейчас',
      'githubLastBackup' => ({required Object date, required Object time}) => 'Проверено: ${date}, ${time}',
      'githubKeepBoth' => 'Сохранить обе версии',
      'githubRestore' => 'Восстановить сейф',
      'githubRestoreHelp' => 'Нужен мастер-пароль выбранной копии. Для работы на нескольких устройствах оставьте привязку включённой. Для независимой копии выключите её. Существующие сейфы не заменяются. Названия зашифрованы, поэтому до открытия видны идентификаторы.',
      'githubNoBackups' => 'Резервных копий пока нет.',
      'githubRestoreError' => 'Не удалось восстановить сейф. Проверьте мастер-пароль и целостность копии.',
      'githubHistoryHelp' => 'История GitHub хранит старые зашифрованные версии: смена мастер-пароля их не отзывает. Отключение удаляет токен с этого устройства; для отзыва удалите его в GitHub → Settings → Developer settings → Personal access tokens.',
      'githubDisconnect' => 'Отключить GitHub',
      'githubClose' => 'Закрыть',
      'githubPending' => 'GitHub · ожидает отправки',
      'githubSetupHelp' => 'GitHub хранит зашифрованные копии ваших сейфов. Настройте подключение один раз по шагам ниже. Регистрация OAuth App или GitHub App не нужна.',
      'githubSetupRepositoryStep' => '1. Место для копий',
      'githubSetupRepositoryHelp' => 'На GitHub выберите свой личный аккаунт, задайте имя репозитория, выберите Private и включите Add a README file. Не добавляйте .gitignore или лицензию. Если репозиторий с копиями уже есть, используйте его.',
      'githubSetupTokenStep' => '2. Ключ доступа',
      'githubSetupTokenHelp' => 'Кнопка ниже открывает создание fine-grained token. Resource owner — ваш аккаунт. Repository access → Only select repositories → только репозиторий копий. Contents → Read and write; Metadata → Read-only. Остальные права не добавляйте. Выберите срок действия, нажмите Generate token и скопируйте github_pat_… в поле ниже.',
      'githubSetupGuide' => 'Открыть подробную инструкцию',
      'githubSetupConnectStep' => '3. Подключение',
      'githubSetupConnectHelp' => 'Вставьте полный адрес репозитория и токен. Подтвердите выбранные права; для нового репозитория с README отметьте подготовку. Нажмите «Подключить» — сохранённые сейфы будут отправлены автоматически. Дождитесь завершения без ошибки.',
      'githubManageTokens' => 'Управлять токенами на GitHub',
      'githubCreateToken' => 'Создать токен GitHub',
      'githubRepositoryAddress' => 'Ссылка на репозиторий',
      'githubToken' => 'Fine-grained token',
      'githubTokenHelp' => 'Хранится под защитой Windows DPAPI и отправляется только GitHub.',
      'githubTokenConfirmation' =>
        'В настройках токена выбран только этот репозиторий; из прав добавлено только Contents → Read and write.',
      'githubInitializeRepository' => 'Это новый репозиторий только с README — подготовить его для копий.',
      'githubConnect' => 'Подключить',
      'githubReplaceToken' => 'Заменить токен',
      'syncNow' => 'Синхронизировать',
      'syncWorking' => 'Обмен с GitHub…',
      'syncDone' => 'Открытый сейф синхронизирован с проверенной версией GitHub. На другом устройстве нажмите «Синхронизировать», чтобы получить изменения.',
      'syncConflicts' => ({
        required Object count,
      }) => 'Сейф синхронизирован. Конфликтов: ${count}. Варианты записей помечены и сохранены. Откройте меню сейфа → Разобрать конфликты, затем синхронизируйте результат.',
      'syncFinishEditing' =>
        'Сначала сохраните или отмените правки и закройте редакторы файлов. Затем синхронизируйте сейф.',
      'syncUnlock' => 'Откройте нужный сейф мастер-паролем. На новом устройстве выберите копию GitHub и включите привязку для синхронизации.',
      'syncKeyChanged' => 'Копия использует другой ключ. Автоматическое объединение отключено: локальные записи не будут зашифрованы ключом этой копии. Текущий сейф сохранён. Можно восстановить удалённую версию отдельным сейфом и проверить её. При раскрытии прежнего пароля подключите локальный сейф к новому репозиторию.',
      'syncLink' => 'Привязать к этой копии для ручной синхронизации между устройствами',
      'syncAlreadyLinked' =>
        'Эта копия уже подключена на этом компьютере. Откройте выбранный сейф и нажмите «Синхронизировать».',
      'syncVaultHelp' => 'Кнопка «Синхронизировать» получает и отправляет изменения открытого сейфа. После первой синхронизации этот сейф обменивается данными только по кнопке. Фонового опроса нет.',
      'syncRollback' => 'Обнаружена старая версия или несовместимая история. Синхронизация остановлена, локальные данные сохранены. Проверьте другие устройства и историю сейфа.',
      'vaultHistory' => 'История и восстановление',
      'vaultHistoryHelp' => 'Выберите зашифрованный снимок. Восстановление создаёт отдельный сейф и требует пароль того времени. Храним до 20 предыдущих состояний на сейф в пределах 256 МиБ.',
      'vaultHistoryEmpty' => 'Предыдущих состояний пока нет.',
      'syncReviewConflicts' => 'Разобрать конфликты',
      'syncReviewHelp' => 'Раскройте варианты для сравнения. Выбор оставит один вариант, остальные останутся в локальной истории. Файлы можно открыть из списка сейфа.',
      'syncNoConflicts' => 'Неразобранных конфликтов записей нет.',
      'syncVariant' => ({required Object id}) => 'Вариант ${id}',
      'syncKeepVariant' => 'Оставить этот вариант',
      'syncKeepVariantQuestion' => 'Оставить выбранный вариант? Другие варианты этой группы будут удалены из текущего сейфа. Предыдущее состояние останется в локальной истории.',
      'syncRelink' => 'Связать с открытым сейфом',
      'syncRelinkHelp' => 'Восстановить связь открытого сейфа с этой копией? Приложение проверит принадлежность и историю. При несовместимой истории связь не будет изменена. Данные отправятся только после нажатия «Синхронизировать».',
      'syncRelinkDone' => 'Связь восстановлена. Нажмите «Синхронизировать» для обмена изменениями.',
      'githubRecoverConnection' => 'Восстановить подключение',
      'githubRecoverConnectionHelp' => 'Журнал подключения повреждён. Сбросить подключение и ввести токен заново? Локальные сейфы и история останутся. Все существующие сейфы перейдут в ручной режим; связь с копиями нужно восстановить кнопкой цепочки рядом с копией.',
      'syncLocalConfirmed' => 'Открытый сейф соответствует последнему подтверждённому обмену.',
      'syncLocalPending' => 'В открытом сейфе есть неподтверждённые изменения.',
      'syncVaultChecked' => ({required Object date}) => 'Этот сейф: ${date}',
      'syncManualOnly' => 'Обмен только по кнопке. Изменения на других устройствах без нажатия не проверяются.',
      'syncShowPassword' => 'Показать или скрыть пароль',
      'sshAdd' => 'Создать SSH-подключение',
      'sshConnect' => 'Подключиться по SSH',
      'sshHost' => 'Адрес сервера (DNS или IP)',
      'sshPort' => 'Порт',
      'sshHelp' => 'Пароль передаётся один раз, по запросу OpenSSH. Доступ к паролю прекращается при блокировке сейфа или через 2 минуты после запуска. Во время входа менеджер не скрывается автоматически. Открытый терминал продолжает работать после блокировки.',
      'sshHostKeyTitle' => 'Ключ SSH-сервера',
      'sshHostKeyHelp' => 'Сверьте отпечаток ключа с владельцем сервера по независимому каналу. Подтверждайте только знакомый сервер. OpenSSH сохранит ключ в known_hosts.',
      'sshTrustHost' => 'Доверять этому ключу',
      'sshStarted' => 'Терминал SSH запущен. При первом подключении подтвердите ключ сервера в SkySecret.',
      'sshClosed' => 'SSH-терминал закрыт.',
      'sshFailed' =>
        'SSH завершился с ошибкой или запуск не удался. Проверьте адрес, доступность сервера, пароль и ключ сервера.',
      'sshMissing' => 'Не найден Windows OpenSSH Client. Установите его в дополнительных компонентах Windows.',
      'sshActive' => 'Для этой записи уже открыт SSH-терминал. Закройте его перед повторным подключением.',
      'sshLimit' => 'Одновременно можно открыть до 8 SSH-терминалов.',
      'sshInvalid' => 'Укажите DNS-имя или IP без команды, порт 1–65535 и пользователя латиницей (буквы, цифры, _, ., -, допустим символ доллара в конце). Пароль обязателен: до 1000 байт UTF-8, без переноса строк и NUL.',
      'captureVisible' => 'Показывать при записи экрана',
      'captureVisibleHelp' => 'Включите, чтобы менеджер и текстовые редакторы были видны на скриншотах, в записи и демонстрации экрана. Содержимое окон может попасть в запись. По умолчанию выключено.',
      'captureSettingFailed' =>
        'Не удалось применить настройку захвата ко всем окнам. Проверьте их видимость в программе записи.',
      'syncKeyChangedTitle' => 'Ключ копии изменился',
      'syncKeepLocal' => 'Оставить локальный сейф',
      'syncOpenRemoteCopy' => 'Восстановить отдельно',
      'browserAll' => 'Все',
      'browserFavorites' => 'Избранное',
      'browserTrash' => ({required Object count}) => 'Корзина (${count})',
      'browserSearch' => 'Поиск',
      'browserSearchHint' => 'Название, логин, сервер или папка',
      'browserCloseSearch' => 'Закрыть поиск',
      'browserTrashHelp' => 'Удалённые записи остаются здесь в зашифрованном виде до окончательного удаления и учитываются в лимитах сейфа. В прежних резервных копиях они могут сохраниться.',
      'browserEmptyTrash' => 'Очистить корзину',
      'browserNoResults' => 'Подходящих записей нет',
      'browserNoFavorites' => 'Отметьте запись звездой, чтобы находить её здесь.',
      'browserTrashEmpty' => 'Корзина пуста',
      'browserFavorite' => 'В избранное',
      'browserUnfavorite' => 'Убрать из избранного',
      'browserRestore' => 'Восстановить',
      'browserDeleteForever' => 'Удалить окончательно',
      'browserDeleteForeverHelp' => ({
        required Object name,
      }) => 'Окончательно удалить «${name}» из этого сейфа? Отменить это действие здесь нельзя. В прежних резервных копиях и истории восстановления запись может сохраниться.',
      'browserEmptyTrashHelp' => ({
        required Object count,
      }) => 'Окончательно удалить записи из корзины: ${count}? Отменить это действие здесь нельзя. В прежних резервных копиях и истории восстановления записи могут сохраниться.',
      'browserMovedToTrash' => 'Перемещено в зашифрованную корзину',
      'browserUndo' => 'Отменить',
      'browserRestored' => 'Запись восстановлена',
      'searchKeyboardHelp' => '↑ ↓ Выбрать   ·   Enter Открыть / скопировать   ·   Esc Закрыть',
      'searchCopyPassword' => 'Скопировать пароль',
      'searchUnavailable' => 'Не удалось открыть поиск. Попробуйте ещё раз.',
      'searchRefine' => 'Первые 50 совпадений. Уточните запрос.',
      'searchStartTyping' => 'Начните вводить название или логин',
      'searchOpenFile' => 'Открыть файл',
      _ => null,
    };
  }
}
