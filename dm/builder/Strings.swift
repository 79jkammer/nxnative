// Slotless's interface language. English is the key and the base: L looks the text up in the table of the chosen language, and a text with no entry stays English. This table is the
// one place in this repository with text in another language, at the player's request: code, comments, logs and the script's own messages stay in English. dm/tools/tests/test_builder_app.py fails when
// a text passed to L has no translation here, or a window's text does not go through L.
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("Same as this Mac")
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

enum Lang {
    static var selected = AppLanguage.system
    static var usesRussian: Bool {
        switch selected {
        case .ru: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        }
    }

    static let russian: [String: String] = [
        // The window
        "1. Your game": "1. Ваша игра",
        "2. Keys": "2. Ключи",
        "2. Where to play": "2. Где играть",
        "3. Where to play": "3. Где играть",
        "Options": "Настройки сборки",
        "Advanced": "Дополнительно",
        "Settings": "Настройки",
        "Choose…": "Выбрать…",
        "Change…": "Изменить…",
        "OK": "ОК",
        "Back": "Назад",
        "Play": "Играть",
        "Done": "Готово",
        "Failed": "Ошибка",
        "Starting…": "Запуск…",
        "Add Game…": "Добавить игру…",
        "Choose Keys…": "Выбрать ключи…",
        "Copy Build Command": "Скопировать команду сборки",
        "Copy Messages": "Скопировать сообщения",
        "Copy Details": "Скопировать подробности",
        "Show messages": "Показывать сообщения",
        "Open Logs": "Открыть журналы",
        "Show in Finder": "Показать в Finder",
        "Build": "Собрать",
        "Build Again": "Собрать снова",
        "Try Again": "Попробовать снова",
        "Cancel Build": "Отменить сборку",
        "Stopping…": "Останавливаю…",
        "Install on iPhone": "Установить на iPhone",
        "Build for Mac": "Собрать для Mac",
        "Stop the build and quit?": "Остановить сборку и выйти?",
        "What the build has finished so far is kept, so the next build goes on from there.": "Уже готовая часть сохранится, и следующая сборка продолжит с этого места.",
        "Stop and Quit": "Остановить и выйти",
        "Keep Building": "Продолжить сборку",

        // Settings
        "Language": "Язык",
        "Same as this Mac": "Как на этом Mac",
        "Language of this app. Game language is set in the game's own settings.": "Язык этой программы. Язык игры меняется в настройках самой игры.",
        "Advanced options": "Расширенные возможности",
        "Shows commands, messages and build options. Not needed to install a game.": "Показывает команды, журналы и настройки сборки. Для установки игры не нужно.",
        "nxnative folder": "Папка nxnative",
        "Not chosen": "Не выбрана",
        "Python": "Python",
        "Found automatically": "Определяется автоматически",

        // Choosing files
        "Choose your game's folder, or one of its .nsp, .nsz, .xci, .xcz or .nup files.": "Выберите папку с игрой или один из её файлов .nsp, .nsz, .xci, .xcz, .nup.",
        "Choose the prod.keys from your console.": "Выберите файл prod.keys со своей консоли.",
        "Choose your nxnative folder.": "Выберите папку nxnative.",
        "Choose a Python 3.12 or newer.": "Выберите Python 3.12 или новее.",
        "Choose this game's build folder.": "Выберите папку сборки для этой игры.",
        "Where should the finished app go?": "Куда сохранить готовое приложение?",
        "This app runs the build script from your nxnative checkout.": "Программа запускает скрипт сборки из вашей папки nxnative.",

        // Where to play
        "iPhone": "iPhone",
        "Mac": "Mac",
        "IPA file": "Файл IPA",
        "An IPA to sideload with AltStore, Sideloadly or LiveContainer. Needs an iPhone 15 Pro or newer, or an iPad with an M1 or later.": "Файл IPA для установки через AltStore, Sideloadly или LiveContainer. Нужен iPhone 15 Pro или новее либо iPad с M1 или новее.",
        "Installs the game on your iPhone over a cable. Needs an iPhone 15 Pro or newer. With a free Apple ID it works for 7 days, then press Reinstall here; your saves stay.": "Установит игру на iPhone по кабелю. Нужен iPhone 15 Pro или новее. С бесплатным Apple ID игра работает 7 дней, затем нажмите здесь «Переустановить»; сохранения останутся.",
        "Makes an app of the game to open on this Mac.": "Создаст приложение с игрой для этого Mac.",

        // Game
        "Reading the game folder…": "Читаю папку с игрой…",
        "Drop your game here": "Перетащите игру сюда",
        "A folder or a file: .nsp, .nsz, .xci, .xcz or .nup. Use a game you own.": "Папка или файл .nsp, .nsz, .xci, .xcz, .nup. Используйте свою игру.",
        "Which game?": "Какая игра?",
        "Game to build": "Игра для сборки",
        "The game is recognized when the build starts.": "Игра определится в начале сборки.",
        "This folder holds %@ games. Choose the one to build.": "В этой папке игр: %@. Выберите нужную.",
        "Ready to build · %@": "Можно собирать · %@",
        "This game can be built.": "Эту игру можно собрать.",
        "This game was not tested with this app. It may not start.": "Эта игра не проверялась с этой программой. Может не запуститься.",
        "Not tested with this app (%@). It may not start.": "С этой программой не проверялась (%@). Может не запуститься.",
        "A folder of the game's files, %@.": "Папка с файлами игры, %@.",
        "All-in-one": "Всё в одном",
        "Game": "Игра",
        "Update": "Обновление",
        "DLC": "DLC",
        "Package": "Пакет",
        "%@ holds no game: no .nsp, .nsz, .xci, .xcz or .nup file, and no base/exefs/main.npdm of a dump.": "В папке «%@» нет игры: ни файлов .nsp, .nsz, .xci, .xcz, .nup, ни дампа с base/exefs/main.npdm.",

        // Keys
        "The keys file (prod.keys) from your own console": "Файл ключей prod.keys с вашей консоли",
        "The file cannot be read.": "Файл не читается.",
        "This file is too big to be a keys file.": "Файл слишком большой для файла ключей.",
        "This is not a text keys file.": "Это не текстовый файл ключей.",
        "No header_key in this file: it is not a complete prod.keys.": "В файле нет header_key: это неполный prod.keys.",

        // Options
        "Version": "Версия",
        "Newest": "Самая новая",
        "Game language": "Язык игры",
        "App name": "Название приложения",
        "The game's name": "Название игры",
        "English (default)": "Английский (по умолчанию)",
        "Japanese": "Японский",
        "French": "Французский",
        "German": "Немецкий",
        "Spanish": "Испанский",
        "Italian": "Итальянский",
        "Dutch": "Нидерландский",
        "Portuguese": "Португальский",
        "Russian": "Русский",
        "Korean": "Корейский",
        "Chinese (Simplified)": "Китайский (упрощённый)",
        "Chinese (Traditional)": "Китайский (традиционный)",
        "English (UK)": "Английский (Великобритания)",
        "French (Canada)": "Французский (Канада)",
        "Spanish (Latin America)": "Испанский (Латинская Америка)",
        "Portuguese (Brazil)": "Португальский (Бразилия)",
        "Keep game files out of the IPA": "Не включать файлы игры в IPA",
        "For a game too big to install: the IPA is small, and the game files are copied to the phone once, with the command shown at the end of the build.": "Для слишком больших игр: IPA будет маленьким, а файлы игры один раз копируются на телефон командой, показанной в конце сборки.",
        "Show the frame rate": "Показывать частоту кадров",
        "Apple team ID": "Team ID Apple",
        "From Xcode": "Из Xcode",
        "Signing identity": "Сертификат подписи",
        "Ad-hoc": "Ad-hoc",
        "Motion controls": "Управление движением",
        "Keep extracted files for the next build": "Сохранять распакованные файлы для следующей сборки",
        "Bundle ID": "Bundle ID",
        "GPU archives": "Архивы для GPU",
        "From the game's profile": "Из профиля игры",
        "GPU architectures to make a pipeline archive for, comma-separated (g18p), or none.": "Архитектуры GPU для архива конвейеров, через запятую (g18p), или none.",
        "Output": "Куда сохранить",
        "Next to the game": "Рядом с игрой",
        "Build folder": "Папка сборки",
        "In the game's folder": "В папке игры",
        "Reset": "Сбросить",
        "Allow a damaged package": "Разрешить повреждённый пакет",
        "Files that fail the hash check are packed as they were read, instead of stopping. Usually a broken copy: dump the game again first.": "Файлы с ошибкой контрольной суммы упаковываются как есть, сборка не останавливается. Обычно это испорченная копия: сначала сделайте дамп заново.",
        "Allow failed shaders": "Разрешить сбойные шейдеры",
        "Shaders that built before and fail now are left out, instead of stopping.": "Шейдеры, которые раньше собирались, а теперь нет, будут пропущены, сборка не остановится.",
        "Allow another Metal compiler": "Разрешить другой компилятор Metal",
        "Build shaders with this Mac's compiler when it is not Xcode 27.2's. They can render wrong pictures.": "Собирать шейдеры компилятором этого Mac, если он не из Xcode 27.2. Картинка может быть неверной.",
        "Use a provisional profile": "Использовать предварительный профиль",
        "Guess the game's settings even though it has a profile, to test the guesses.": "Угадывать настройки игры, даже если профиль есть, чтобы проверить догадки.",

        // Getting ready
        "This Mac": "Этот Mac",
        "Getting this Mac ready": "Подготовка Mac",
        "Checking this Mac…": "Проверяю этот Mac…",
        "Check Again": "Проверить снова",
        "This Mac is ready.": "Этот Mac готов.",
        "Everything a build needs is installed.": "Всё нужное для сборки установлено.",
        "Install Everything": "Установить всё",
        "Install in Terminal": "Установить в Терминале",
        "Free tools": "Бесплатные инструменты",
        "The app installs these by itself: %@.": "Программа установит их сама: %@.",
        "No password is needed. This can take several minutes, and you can use your Mac meanwhile.": "Пароль не нужен. Это может занять несколько минут, а Mac пока можно использовать.",
        "Installing %@ (%@ of %@)…": "Устанавливаю: %@ (%@ из %@)…",
        "Runs %@ above.": "Выполнит команды выше: %@.",
        "Use Another Python…": "Выбрать другой Python…",
        "Build anyway": "Всё равно собрать",
        "The script checks again when it starts, and stops with the reason.": "Скрипт проверит всё сам при запуске и остановится, назвав причину.",
        "Installed (%@)": "Установлено (%@)",
        "Choose the nxnative folder to check this Mac.": "Выберите папку nxnative, чтобы проверить этот Mac.",
        "A first build takes 30–60 minutes and needs about twice the game's size plus 10 GB free. Building again is much faster.": "Первая сборка занимает 30–60 минут и требует свободного места: примерно два размера игры плюс 10 ГБ. Повторные сборки намного быстрее.",
        "The first build needs about %@ free on this disk; it has %@.": "Для первой сборки нужно около %@ на этом диске, а свободно %@.",
        "%@ could not be installed: %@": "Не удалось установить %@: %@",
        "The setup script could not be written: %@": "Не удалось записать скрипт установки: %@",

        // What stops a build
        "Choose the nxnative folder.": "Выберите папку nxnative.",
        "Add your game.": "Добавьте игру.",
        "This folder holds several games: choose one under Game, on the left.": "В папке несколько игр: выберите одну слева, в разделе с игрой.",
        "Add your prod.keys.": "Добавьте файл prod.keys.",
        "Choose a working prod.keys.": "Выберите рабочий файл prod.keys.",
        "Connect your iPhone.": "Подключите iPhone.",
        "Create your signing certificate in Xcode.": "Создайте сертификат подписи в Xcode.",
        "Add your Apple ID in Xcode.": "Добавьте Apple ID в Xcode.",
        "Install Python first.": "Сначала установите Python.",
        "Install what this Mac is missing.": "Установите то, чего не хватает на этом Mac.",
        "Installing…": "Устанавливаю…",

        // What a Mac needs
        "macOS 26.6 or later": "macOS 26.6 или новее",
        "This Mac has %@.": "На этом Mac версия %@.",
        "Xcode 27.2": "Xcode 27.2",
        "%@ in %@": "%@ в %@",
        "Xcode is Apple's free app for building apps, and it is large. Download Xcode 27.2, move it to Applications, then come back here.": "Xcode — бесплатная программа Apple для сборки приложений, она большая. Скачайте Xcode 27.2, переместите в «Программы» и вернитесь сюда.",
        "Open the download page": "Открыть страницу загрузки",
        "Metal compiler": "Компилятор Metal",
        "The Metal toolchain is a separate download.": "Инструменты Metal скачиваются отдельно.",
        "iOS platform": "Платформа iOS",
        "Install it in Xcode → Settings → Components.": "Установите в Xcode → Settings → Components.",
        "Homebrew": "Homebrew",
        "A free installer for developer tools. It opens in Terminal and asks for your Mac's password: type it there, the letters stay invisible. Then come back here.": "Бесплатный установщик инструментов для разработчиков. Откроется Терминал и спросит пароль от Mac: введите его там, символы не отображаются. Затем вернитесь сюда.",
        "Install Homebrew": "Установить Homebrew",
        "Installed after Homebrew.": "Установится после Homebrew.",
        "It runs the shader translator.": "Нужен для перевода шейдеров.",
        "Python modules": "Модули Python",
        "Python %@: %@": "Python %@: %@",
        "Missing from Python %@: %@.": "В Python %@ нет: %@.",
        "Python modules for some games": "Модули Python для некоторых игр",
        "Missing: %@.": "Нет: %@.",
        "This game's .nsz or .xcz files need nsz.": "Файлам .nsz и .xcz этой игры нужен nsz.",
        "Needed for .nsz / .xcz files and for games on newer system versions.": "Нужны для файлов .nsz и .xcz и для игр на новых версиях системы.",
        "Python 3.12 or newer": "Python 3.12 или новее",
        "No arm64 Python 3.12 or newer was found.": "Python 3.12 или новее для arm64 не найден.",
        "The tested Metal compiler": "Проверенный компилятор Metal",

        // What an iPhone needs
        "Apple ID in Xcode": "Apple ID в Xcode",
        "Free team %@: apps last 7 days, 3 at a time.": "Бесплатная команда %@: приложения работают 7 дней, не больше 3 одновременно.",
        "Team %@.": "Команда %@.",
        "Add yours in Xcode → Settings → Apple Accounts. A free one is enough; your password stays in Xcode.": "Добавьте свой в Xcode → Settings → Apple Accounts. Подойдёт и бесплатный, пароль останется в Xcode.",
        "Open Xcode": "Открыть Xcode",
        "Signing certificate": "Сертификат подписи",
        "Your Apple ID is added; one step left. In Xcode → Settings → Apple Accounts, select your account, click Manage Certificates, then + → Apple Development. This app reads your team from that certificate. Or enter the team ID under Advanced.": "Apple ID добавлен, остался один шаг. В Xcode → Settings → Apple Accounts выберите аккаунт, нажмите Manage Certificates, затем + → Apple Development. Программа возьмёт команду из этого сертификата. Или введите Team ID в разделе «Дополнительно».",
        "Connect it with a cable, unlock it, and tap Trust.": "Подключите кабелем, разблокируйте и нажмите «Доверять».",
        "%@: %@, by cable": "%@: %@, по кабелю",
        "%@: %@, over the network": "%@: %@, по сети",
        "Developer Mode": "Режим разработчика",
        "On the iPhone: Settings → Privacy & Security → Developer Mode, turn it on, and let it restart.": "На iPhone: Настройки → Конфиденциальность и безопасность → Режим разработчика. Включите и дождитесь перезагрузки.",
        "iPhone model": "Модель iPhone",
        "%@ cannot run these games: they need an iPhone 15 Pro or newer.": "%@ не запустит эти игры: нужен iPhone 15 Pro или новее.",

        // The build
        "Stage %@ of %@: %@": "Этап %@ из %@: %@",
        "about %@ left in this stage": "до конца этапа около %@",
        "%@ of %@": "%@ из %@",
        "Shaders must be rebuilt (the translation chain changed): %@ libraries": "Шейдеры нужно пересобрать (изменилась цепочка перевода): библиотек %@",
        "Shaders must be rebuilt (the game profile's shader inputs changed): %@ libraries": "Шейдеры нужно пересобрать (изменились данные профиля игры): библиотек %@",
        "Preparing tools": "Готовлю инструменты",
        "Studying the game": "Изучаю игру",
        "Unpacking the game": "Распаковываю игру",
        "Adapting the game": "Адаптирую игру",
        "Preparing the graphics (the longest step)": "Готовлю графику (самый долгий этап)",
        "Testing the game": "Проверяю игру",
        "Building the app": "Собираю приложение",

        // Results
        "%@ is on %@": "%@ на устройстве %@",
        "First time: on the iPhone, go to Settings → General → VPN & Device Management and trust your Apple ID, then open the game from the Home Screen.": "В первый раз: на iPhone откройте Настройки → Основные → VPN и управление устройством и доверьте своему Apple ID. Затем запустите игру с экрана «Домой».",
        "It works until %@. Reinstall from here to renew it; saves stay.": "Работает до %@. Чтобы продлить, переустановите отсюда; сохранения останутся.",
        "Built without Increased Memory Limit, which this Apple ID cannot give: iOS may close bigger games.": "Собрано без Increased Memory Limit: этот Apple ID его не даёт, и iOS может закрывать большие игры.",
        "%@ is ready": "%@ готова",
        "Install the IPA with a sideloading tool such as AltStore, Sideloadly or LiveContainer. Turn on Increased Memory Limit if the tool offers it.": "Установите IPA через AltStore, Sideloadly или LiveContainer. Если программа предлагает Increased Memory Limit, включите его.",
        "The build stopped": "Сборка остановилась",
        "Press Try Again. If it stops again, press Copy Details and send the text to whoever helps you.": "Нажмите «Попробовать снова». Если сборка снова остановится, нажмите «Скопировать подробности» и отправьте текст тому, кто вам помогает.",
        "Build cancelled": "Сборка отменена",
        "What was finished is kept: the next build goes on from there.": "Готовая часть сохранена: следующая сборка продолжит с этого места.",
        "The build stopped with exit code %@.": "Сборка остановилась с кодом %@.",
        "%@ did not start: %@": "%@ не запустился: %@",
        "On %@": "На устройстве %@",
        "The signature ended on %@: reinstall to play.": "Подпись закончилась %@: чтобы играть, переустановите.",
        "Works until %@.": "Работает до %@.",
        "Without Increased Memory Limit: iOS may close bigger games.": "Без Increased Memory Limit: iOS может закрывать большие игры.",
        "Reinstall": "Переустановить",
        "Copy Game Files Again": "Скопировать файлы игры заново",
        "Only after deleting the app from the iPhone, which deletes its game files and saves too.": "Только если удаляли приложение с iPhone: это удаляет и файлы игры, и сохранения.",
        "Reinstalling keeps your saves. Deleting the app from the iPhone does not.": "Переустановка сохраняет прогресс. Удаление приложения с iPhone — нет.",

        // The install
        "Sign and build for %@": "Подпись и сборка для %@",
        "Install on %@": "Установка на %@",
        "sending the app": "отправляю приложение",
        "starting": "запуск",
        "Game files": "Файлы игры",
        "already on the phone": "уже на телефоне",
        "Copy game files to %@": "Копирование файлов игры на %@",
        "this can take minutes; keep the iPhone unlocked": "это может занять несколько минут; не блокируйте iPhone",
        "without Increased Memory Limit": "без Increased Memory Limit",
        "This Apple ID cannot give the app Increased Memory Limit: building without it. Bigger games may be closed by iOS.": "Этот Apple ID не даёт приложению Increased Memory Limit: собираю без него. iOS может закрывать большие игры.",
        "The iPhone or the Apple team is gone: connect it and try again.": "iPhone или команда Apple недоступны: подключите и попробуйте снова.",
        "The prepared Xcode project lists no scheme: build the game again.": "В подготовленном проекте Xcode нет схемы: соберите игру заново.",
        "Xcode does not say where it built the app.": "Xcode не сообщил, где собрал приложение.",
        "The script did not say which project it prepared.": "Скрипт не сообщил, какой проект подготовил.",
        "The prepared project is gone: press Build to make it again.": "Подготовленный проект исчез: нажмите кнопку сборки, чтобы создать его заново.",
        "This account cannot give the app Increased Memory Limit.": "Этот аккаунт не даёт приложению Increased Memory Limit.",
        "Xcode has no working Apple ID for this team. Add it in Xcode → Settings → Apple Accounts, then try again.": "В Xcode нет рабочего Apple ID для этой команды. Добавьте его в Xcode → Settings → Apple Accounts и попробуйте снова.",
        "Apple refuses this bundle ID. Enter another one under Advanced, then build again.": "Apple отклоняет этот Bundle ID. Укажите другой в разделе «Дополнительно» и соберите снова.",
        "This free Apple ID reached Apple's limit of apps. Delete an app signed with it from the iPhone, or wait up to 7 days.": "Этот бесплатный Apple ID достиг лимита приложений. Удалите с iPhone подписанное им приложение или подождите до 7 дней.",
        "Unlock the iPhone and keep it unlocked, then try again.": "Разблокируйте iPhone, не блокируйте его и попробуйте снова.",
        "Turn on Developer Mode on the iPhone: Settings → Privacy & Security → Developer Mode, then restart it.": "Включите режим разработчика на iPhone: Настройки → Конфиденциальность и безопасность → Режим разработчика, затем перезагрузите его.",
        "The step failed: its log is in the game's logs folder.": "Шаг не выполнился: его журнал лежит в папке logs игры.",

        // Getting the app's components
        "Getting ready": "Подготовка",
        "Downloading the app's components (about 200 MB)…": "Скачиваю компоненты программы (около 200 МБ)…",
        "Downloading the app's components…": "Скачиваю компоненты программы…",
        "The app's components are not downloaded.": "Компоненты программы не скачаны.",
        "This happens once.": "Это нужно сделать один раз.",
        "The download did not finish. Check your internet connection.": "Загрузка не завершилась. Проверьте подключение к интернету.",

        // Controls
        "Controls": "Управление",
        "A controller is recommended": "Рекомендуем геймпад",
        "Most 3D games are much easier with one: a DualSense, an Xbox controller, a Switch Pro Controller, or one that holds the phone, such as Backbone or Razer Kishi. Pair it in Settings → Bluetooth, or plug it in. The buttons on the screen hide by themselves while it is connected.": "В большинство 3D-игр с ним играть намного удобнее: DualSense, геймпад Xbox, Switch Pro Controller или держатель для телефона вроде Backbone или Razer Kishi. Подключите его в Настройки → Bluetooth или кабелем. Кнопки на экране скроются сами, пока он подключён.",
        "Playing by touch? In the game, open the menu (the gear at the top) and choose Edit on-screen buttons to move, resize or hide them.": "Играете касаниями? В игре откройте меню (шестерёнка вверху) и выберите Edit on-screen buttons, чтобы переместить, изменить или скрыть кнопки.",
        "Vibration, camera direction, trackpad camera on the Mac and the size of the buttons on the screen are on the settings screen each game shows before it starts.": "Вибрация, направление камеры, камера на трекпаде Mac и размер кнопок на экране — на экране настроек, который игра показывает перед запуском.",
        "Keyboard (on the Mac)": "Клавиатура (на Mac)",
        "Controller: what each button presses": "Геймпад: что нажимает каждая кнопка",
        "An iPhone game gets these when it is built. A Mac game gets them at its next start.": "Игра на iPhone получит это при следующей сборке, игра на Mac — при следующем запуске.",
        "Press a key…": "Нажмите клавишу…",
        "No key": "Нет клавиши",
        "D-pad up": "Крестовина вверх",
        "D-pad down": "Крестовина вниз",
        "D-pad left": "Крестовина влево",
        "D-pad right": "Крестовина вправо",
        "Press the left stick": "Нажатие левого стика",
        "Press the right stick": "Нажатие правого стика",
        "Left stick up": "Левый стик вверх",
        "Left stick down": "Левый стик вниз",
        "Left stick left": "Левый стик влево",
        "Left stick right": "Левый стик вправо",
        "Right stick up": "Правый стик вверх",
        "Right stick down": "Правый стик вниз",
        "Right stick left": "Правый стик влево",
        "Right stick right": "Правый стик вправо",
        "Shake": "Встряхнуть",

        // Cleaning up
        "Free up space": "Освободить место",
        "%@ (%@)": "%@ (%@)",
        "Move to Trash": "Переместить в Корзину",
        "Moved to the Trash. Empty the Trash to free the space.": "Перемещено в Корзину. Очистите её, чтобы освободить место.",
        "Some files could not be moved to the Trash: %@": "Не все файлы удалось переместить в Корзину: %@",
        "If you will not build more games, you can also delete Xcode from Applications yourself: it takes many gigabytes.": "Если больше не будете собирать игры, можете сами удалить Xcode из «Программ»: он занимает много гигабайт.",
        "Temporary build files": "Временные файлы сборки",
        "Safe to remove. Reinstall makes them again.": "Можно удалить: при переустановке они создадутся заново.",
        "All build files": "Все файлы сборки",
        "The game stays on the iPhone, but Reinstall will not work: after 7 days you would build it again from the game files.": "Игра останется на iPhone, но «Переустановить» работать не будет: через 7 дней придётся собирать её заново из файлов игры.",
        "Build files": "Файлы сборки",
        "The finished game does not need them. Building it again takes longer.": "Готовой игре они не нужны. Повторная сборка займёт больше времени.",
        "The game's original files": "Исходные файлы игры",
        "Keep them if you may build this game again: without them you would need to copy them from your console again.": "Оставьте их, если можете собирать эту игру снова: иначе придётся заново копировать их с консоли.",

        // Adding files
        "Put one game's files in one folder, then add that folder: the update and DLC are found beside the game.": "Сложите файлы одной игры в одну папку и добавьте её: обновление и DLC найдутся рядом с игрой.",
        "Add a game folder, a .nsp, .nsz, .xci, .xcz or .nup file, or prod.keys.": "Добавьте папку с игрой, файл .nsp, .nsz, .xci, .xcz, .nup или prod.keys.",
        "%@ is not an nxnative checkout: it has no scripts/build_ipa_from_nsp.py.": "«%@» не папка nxnative: в ней нет scripts/build_ipa_from_nsp.py.",
    ]
}

// The text in the chosen language. %@ takes a String, in the order given.
func L(_ text: String, _ args: CVarArg...) -> String {
    let format = Lang.usesRussian ? Lang.russian[text] ?? text : text
    return args.isEmpty ? format : String(format: format, arguments: args)
}

// The script's stage, in words for someone who does not know its tools. Names no rule covers stay as they are: the install's own are already in words.
func friendlyStage(_ name: String) -> String {
    if name.contains("nx_extract") || name == "build ID lookup" { return L("Preparing tools") }
    if name.hasPrefix("survey") { return L("Studying the game") }
    if name.hasPrefix("extract") || name.hasPrefix("decompress") || name.hasPrefix("pack ") { return L("Unpacking the game") }
    if name == "rewrite" { return L("Adapting the game") }
    if name.lowercased().contains("shader") || name.hasPrefix("Pipeline") { return L("Preparing the graphics (the longest step)") }
    if name == "heap check" || name == "address regions" { return L("Testing the game") }
    if ["prepare Xcode", "app build", "IPA pack", "Mac app", "Mac host"].contains(name) { return L("Building the app") }
    return name
}
