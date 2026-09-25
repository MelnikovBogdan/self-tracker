# Self Tracker

Личный трекер для Android и macOS. В репозитории есть Flutter-клиент и локально запускаемый API. Сейчас приложение умеет входить в учётную запись владельца, менять отображаемое имя и получать подтверждённое значение на другом устройстве. Отдельные активности подключаются модулями на следующих этапах.

## Структура

- `apps/client` — Flutter-приложение для Android и macOS.
- `apps/api` — TypeScript/Fastify API, миграции PostgreSQL и интеграционные тесты.
- `openspec/specs` — актуальные требования; `openspec/changes/archive/2026-09-24-bootstrap-self-tracker-foundation` — план первого этапа.

## Требования к локальной среде

Node.js 24, pnpm 10, Docker Desktop и [Flutter SDK](https://docs.flutter.dev/get-started/install). Для сборки Android нужны [Android SDK и Java](https://docs.flutter.dev/platform-integration/android/setup); для macOS нужна [полная установка Xcode](https://docs.flutter.dev/platform-integration/macos/setup) и CocoaPods. Проверка установки: `flutter doctor -v`.

## Запуск API

Из корня репозитория:

```sh
pnpm install
docker compose up -d db
cp apps/api/.env.example apps/api/.env
pnpm db:migrate
pnpm owner:create
pnpm dev:api
```

Команда `owner:create` спрашивает логин и пароль в терминале. Она создаёт единственного владельца и не позволяет создать второго. Пароль не задаётся в файлах проекта. PostgreSQL доступен локально на порту `55432`, API — на `127.0.0.1:3000`. Проверка API: `curl http://127.0.0.1:3000/health`. Машинно читаемый контракт находится по адресу `/openapi.json`.

Если тестовая БД не появилась из-за ранее созданного Docker volume, создайте её один раз:

```sh
docker compose exec -T db psql -U tracker -d postgres -c 'CREATE DATABASE self_tracker_test'
```

## Запуск клиента

Сначала выполните `flutter pub get` в `apps/client`. В debug-сборках адрес API можно передать через `--dart-define=API_BASE_URL=...`:

```sh
cd apps/client
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:3000
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

`10.0.2.2` — адрес компьютера из стандартного Android-эмулятора. Для физического телефона запустите API с `API_HOST=0.0.0.0` в `apps/api/.env`, подключите телефон и Mac к одной сети и укажите `http://<локальный-ip-mac>:3000`. Локальный HTTP допускается только в debug-сборке; для остальных сборок клиент требует HTTPS.

Проверка устанавливаемых debug-сборок:

```sh
cd apps/client
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000
flutter build macos --debug --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

APK появится в `apps/client/build/app/outputs/flutter-apk/`, приложение macOS — в `apps/client/build/macos/Build/Products/Debug/`. Публикация сервера и производственная подпись приложений выполняются на следующих этапах.

## Проверки

```sh
pnpm typecheck
pnpm test
cd apps/client
flutter analyze
flutter test
```

`pnpm test` использует только БД `self_tracker_test` и очищает данные владельца в ней перед тестами. Основная БД `self_tracker` не затрагивается. Сквозная проверка: войдите на Android и macOS, измените имя на одном устройстве, обновите профиль на другом, затем выйдите на одном устройстве и убедитесь, что вторая сессия продолжает работать.

Автоматизированный сценарий для реальных платформ находится в `apps/client/integration_test/sync_smoke_test.dart`. Запустите API с отдельной тестовой БД и временным владельцем, затем выполните `flutter test integration_test/sync_smoke_test.dart -d macos` или укажите ID Android-эмулятора. Передайте через `--dart-define` значения `API_BASE_URL`, `SMOKE_USERNAME` и `SMOKE_PASSWORD`. Для последовательной проверки Android → macOS → Android задайте `SMOKE_SECOND_NAME` на первой платформе и такое же `SMOKE_EXPECTED_NAME` на следующей.

## Синхронизация и модули

Клиент обновляет профиль при открытии экрана и по кнопке «Обновить». Изменение отправляется вместе с ревизией; сервер подтверждает новую ревизию или возвращает конфликт, если профиль уже изменён на другом устройстве. Автономное редактирование пока не включено.

Новый модуль активности объявляет ID, название и экраны в `apps/client/lib/activities`, а на сервере регистрирует маршруты под `/v1/activities/<id>` и собственные миграции. Общих полей для записей чтения, программирования и других активностей нет.
