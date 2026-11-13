# VPN Guard

Локальное desktop-приложение для **macOS и Windows** с общим интерфейсом на **Flutter**.
Цель: разрешать выбранным приложениям доступ только через проверенный VPN-маршрут.
Соединение устанавливает Amnezia; VPN Guard должен управлять системной блокировкой.
Аккаунт VPN Guard и собственный сервер продукта не требуются.

**Статус: начальный прототип, не средство защиты.** Flutter-приложение уже можно
запустить, но оно пока не блокирует трафик. Совместимость фильтра с Amnezia и отсутствие
утечек не проверены. Нельзя использовать эту версию для защиты Claude или ChatGPT.

## Что есть

| Компонент | Состояние |
|---|---|
| Flutter UI для macOS/Windows | Экран состояния, диагностика, обработка отсутствующего backend |
| macOS-фильтр | Собираемый `NEFilterDataProvider`, блокировка только тестового процесса; установка не проверена |
| macOS Lab | Отдельный технический установщик экспериментального фильтра |
| Генератор трафика | Swift CLI, постоянные TCP/UDP-соединения, числовые IPv4/IPv6-адреса, JSONL |
| Испытательный endpoint | Python TCP/UDP echo, по умолчанию только loopback |
| Windows WFP Service | Ещё не реализована |
| IP, геолокация, допуск через VPN | Ещё не реализованы |
| Rust-ядро, XPC / Named Pipe | После проверки системных механизмов |

Flutter — основной интерфейс продукта на обеих ОС. `macos/Host` — временная
лабораторная утилита для испытания расширения, не второй продуктовый интерфейс.
Flutter не принимает решения о разрешении сетевого трафика.

## Запуск приложения

Используемая версия: Flutter **3.50.0**, Dart **3.14.0**. Зависимости зафиксированы в
`apps/desktop/pubspec.lock`. Текущий Flutter использует пакет `material_ui`.

### macOS

Нужны Flutter и Xcode с macOS SDK. Для запуска **интерфейса** платный Apple Developer
не нужен.

```sh
cd apps/desktop
flutter pub get
flutter run -d macos
```

Сборка локального приложения:

```sh
flutter build macos --debug
open "build/macos/Build/Products/Debug/VPN Guard.app"
```

### Windows

Нужны Flutter и Visual Studio с компонентами Desktop development with C++.
Команды выполняются на Windows; macOS не собирает Windows-бинарник.

```powershell
cd apps/desktop
flutter pub get
flutter run -d windows
```

Сборка: `flutter build windows --release`. Рабочая папка приложения —
`build/windows/x64/runner/Release/`; для переноса нужны все файлы этой папки.
Windows-сборка и запуск пока не проверены на реальной Windows.

## Проверки

Из `apps/desktop`:

```sh
flutter analyze
flutter test
```

На Mac из корня репозитория:

```sh
swift test
python3 tools/smoke_probe.py
```

Smoke-тест запускает локальный echo endpoint, проверяет TCP/UDP по `127.0.0.1` и
`::1`, затем останавливает endpoint. Он **не проверяет VPN или системный фильтр**.
Unit-тесты отдельно проверяют идентификацию тестового процесса и валидацию аргументов.

В `.github/workflows/ci.yml` подготовлены проверки Flutter на macOS/Windows,
сборки desktop UI и unsigned-сборка macOS Lab. Запуск CI в GitHub ещё не выполнялся.

## Прототип фильтра macOS

Собрать без сертификата:

```sh
xcodebuild -project macos/VPNGuardLab.xcodeproj \
  -scheme VPNGuardLab -configuration Debug \
  -derivedDataPath build/lab CODE_SIGNING_ALLOWED=NO build
```

Компиляция без подписи **не даёт возможности установить системное расширение**.
Для штатной установки понадобятся Apple Developer, подходящие entitlements,
подписи и provisioning profiles. Для распространяемого выпуска также нужна
notarization. Наличие исходников на GitHub не отменяет эти требования.
Отключение SIP не входит в поддерживаемый процесс разработки.

Подробности: [macOS-прототип](docs/macos-prototype.md).

## Структура

```text
apps/desktop/        Flutter UI и launchers macOS/Windows
macos/Filter/       Экспериментальный системный фильтр
macos/Host/         Техническая утилита установки/удаления фильтра
macos/*.xcodeproj   Готовый Xcode-проект лаборатории
Sources/GuardCore/  Политика блокировки probe и проверка CLI-аргументов
Sources/GuardProbe/ Генератор TCP/UDP-трафика для macOS
Tests/             Swift-тесты
tools/             Echo endpoint, smoke-тест, генератор Xcode-проекта
docs/              Ограничения, план испытаний и результаты
```

Swift Package — временная часть macOS-стенда. Общую продуктовую политику допуска
планируется вынести в Rust после проверки прототипов macOS и Windows.

## Следующие этапы

1. Установить подписанный macOS-фильтр и подтвердить блокировку тестового процесса.
2. Выбрать и проверить постоянный запрет выхода вне Amnezia, включая уже открытые
   TCP/UDP-соединения. Текущий фильтр **не привязывает** потоки к VPN.
3. Создать Windows Service + WFP-прототип и провести такие же испытания.
4. Реализовать проверку IP/страны, поколения соединений, таймауты и отзыв допуска.
5. Подключить backend к Flutter через нативные адаптеры и защищённый IPC.
6. Покрыть реальные приложения и их helpers, DNS, сон, перезагрузку и обновления.

Матрица и критерии: [план испытаний](docs/test-matrix.md).
Фактические результаты: [журнал проверки](docs/verification.md).

