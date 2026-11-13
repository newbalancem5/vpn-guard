# macOS: лаборатория системного фильтра

Это этап проверки системного API, а не готовый kill switch. У прототипа нет режима
«разрешить через VPN». Он должен блокировать новые потоки только `guard-probe`.

**Текущий стенд отключён:** после успешного локального теста пользователь сообщил
об обрывах интернета с Amnezia; связь восстанавливалась переподключением VPN.
В сборке 3 исправлен отсутствовавший `stopFilter` и добавлена кнопка отключения,
но причина обрывов во время работы ещё не установлена. Не считать это исправлением
совместимости и не включать фильтр на рабочей машине до отдельного повторного испытания.

## Сборка и baseline без Apple Developer

Из корня:

```sh
swift test
codesign --force --sign - --identifier org.vpnguard.prototype.probe .build/debug/guard-probe
codesign -dv .build/debug/guard-probe
python3 tools/smoke_probe.py
```

Ad-hoc-подпись задаёт стабильный signing identifier **только тестовому CLI**.
Она не подходит для установки System Extension. После пересборки CLI подпись
нужно повторить. Фильтр ищет именно этот идентификатор, а не имя процесса.

Собрать лабораторию:

```sh
xcodebuild -project macos/VPNGuardLab.xcodeproj -scheme VPNGuardLab \
  -configuration Debug -derivedDataPath build/lab CODE_SIGNING_ALLOWED=NO build
```

Результат: `build/lab/Build/Products/Debug/VPNGuardLab.app` с вложенным
`Contents/Library/SystemExtensions/*.systemextension`.
Unsigned-артефакт служит проверкой компиляции, не установочным пакетом.

Xcode-проект включён в репозиторий. Ruby и gem `xcodeproj` пользователю не нужны;
`tools/generate_lab_project.rb` — вспомогательный инструмент сопровождающего.

## Штатная подписанная установка — проверена на текущем Mac

1. Открыть `macos/VPNGuardLab.xcodeproj` в Xcode.
2. Выбрать одну Apple Developer Team для обоих targets. Установить уникальный
   `BUNDLE_PREFIX` в Build Settings проекта; host использует его для поиска расширения.
3. Настроить provisioning profiles/capabilities для Network Extensions (Content Filter),
   System Extension installation и общей App Group. Mach service расширения должен
   находиться внутри этой группы. Entitlements включены в исходники, но сами по
   себе они не являются разрешением Apple.
   Для разработки с Apple Development используется `content-filter-provider`.
   Для будущего распространения через Developer ID понадобятся соответствующие
   профили и вариант entitlement `content-filter-provider-systemextension`.
4. Собрать подписанную лабораторию. Поместить её в `/Applications`.
5. Запустить baseline CLI с указанным signing identifier при **выключенном** фильтре.
6. В Lab нажать «Установить», подтвердить запрос macOS и затем «Включить».
7. Проверить состояние расширения и журнал. «Конфигурация сохранена» не означает,
   что фильтр действительно применяет решения.

```sh
systemextensionsctl list
log stream --style compact --predicate 'subsystem == "org.vpnguard.prototype"'
```

8. Запустить **новый** процесс probe. Должен появиться `Dropping probe flow`, а
   подконтрольный внешний endpoint не должен получить probe-трафик. Повторить для
   IPv4/IPv6, TCP/UDP и несвязанного контрольного приложения.
9. Удалять через «Удалить фильтр»: сначала удаляется собственная конфигурация,
   затем запрашивается деактивация расширения. macOS может потребовать перезагрузку.
   Простое удаление `.app` не считается проверенной процедурой удаления.

Для временного отключения в сборке 3 есть отдельная кнопка «Отключить фильтр»:
она сохраняет `isEnabled = false` только для собственной конфигурации. Регистрация
System Extension остаётся установленной; `systemextensionsctl list` сам по себе
не показывает, применяет ли конфигурация фильтра решения. Закрытие окна Lab также
не отключает фильтрацию. При обрыве связи сначала отключить конфигурацию и проверить
сеть; не сбрасывать настройки сторонних VPN и фильтров.

На стенде 13 ноября сборка 2 прошла `python3 tools/smoke_probe.py --expect-blocked`:
новые probe-потоки IPv4/IPv6 TCP/UDP заблокированы, контрольные соединения разрешены,
каждому протоколу соответствует запись `Dropping probe flow`. Это loopback-тест,
не проверка VPN-утечек. После отключения обычный `tools/smoke_probe.py` снова прошёл.

## Внешний endpoint

На отдельном контролируемом устройстве или сервере:

```sh
python3 tools/echo_server.py --host 0.0.0.0 --port 54321
```

Для IPv6 — отдельный запуск с подходящим адресом, например `--host ::`.
Открывать порт только для теста и ограничивать доступ стендом. Endpoint принимает
TCP/UDP на одном порту, записывает адрес отправителя и размер, но не содержимое.
Передаваемые probe-данные не содержат токенов, переписки или конфигурации VPN.

На Mac заменить `TEST_ENDPOINT_IP` на числовой адрес подконтрольного сервера:

```sh
.build/debug/guard-probe --host TEST_ENDPOINT_IP --transport tcp --duration 60 --require-echo
.build/debug/guard-probe --host TEST_ENDPOINT_IP --transport udp --duration 60 --require-echo
```

Оба запуска используют постоянное соединение. Для проверки новых соединений
запускать новые процессы до/после изменения сети. Код возврата `2` означает ошибку
или отсутствие обязательного echo; это **не доказательство работы фильтра**.
Сначала нужен успешный baseline с тем же endpoint и доступностью маршрута.
`send_queued` подтверждает лишь приём данных локальным стеком; `echo_received` —
точное совпадение ответа с отправленным кадром.

Для исследования утечек одновременно нужны захваты физического интерфейса и
туннеля, серверный журнал и журнал фильтра. Имена интерфейсов выбирать по факту
на стенде, не считать любой `utun` интерфейсом Amnezia. DNS и QUIC проверяются отдельно.

## Известные ограничения

- Идентификация probe через audit token и Security.framework подтверждена
  в установленном sandboxed provider сборки 2. Реальные приложения не проверены.
- Проверяются responsible app и socket owner. Если оба не дают подтверждённого
  решения, unknown-трафик разрешается и логируется как неполное покрытие.
  Это осознанное ограничение лаборатории: нельзя блокировать весь компьютер из-за
  ошибки идентификации. Такой режим не подходит для обещания fail-closed защиты.
- signing identifier используется только для отказа тестовому процессу; доверенная
  идентичность реальных приложений и подписи ещё не реализованы.
- Не проверены уже существующие потоки, сбои provider, загрузка до приложений,
  DNS, helpers, QUIC, IPv6 вне VPN и удаление на реальной системе.
- Имя туннеля, процесс Amnezia и успешный IP-check пока не используются для допуска.
- Flutter с лабораторией пока не связан. Lab не меняет правила Amnezia.

Основания: [Apple deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment),
[Network filtering sample](https://developer.apple.com/documentation/networkextension/filtering-network-traffic),
[NEFilterDataProvider](https://developer.apple.com/documentation/networkextension/nefilterdataprovider).

