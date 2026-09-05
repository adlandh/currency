# readme Specification

## Purpose

Определяет содержание README проекта: какое описание сервиса, инструкции запуска, проверки и развёртывания он должен давать читателю, и какие упоминания из него исключаются.

## Requirements

### Requirement: Service overview in README

README SHALL описывать сервис: назначение (справочные курсы валют и пересчёт сумм), платформу (Flutter Web), источник данных (Frankfurter, загрузка в браузере без серверной части) и характер сохраняемых настроек (базовая валюта и список таблицы в `localStorage` сайта). README также SHALL сохранять раздел об ограничениях данных Frankfurter.

#### Scenario: New developer reads the overview
- **WHEN** читатель открывает README, не зная ничего о проекте
- **THEN** из первых разделов он понимает, что это за сервис, на чём работает, откуда берёт данные и что сохраняется в браузере

### Requirement: Run instructions in README

README SHALL документировать запуск приложения в режиме разработки: требуемые версии Flutter/Dart, команды `task serve` и `flutter run -d web-server` (с `flutter pub get` при необходимости), адрес dev-сервера `http://localhost:8080` из `web_dev_config.yaml`, замечание о необходимости одного браузера и профиля для сохранения списка валют, предупреждение не открывать `web/index.html` через `file://` и заметку о конфигурации запуска в GoLand/IntelliJ.

#### Scenario: Developer starts the app from README alone
- **WHEN** разработчик с установленными Flutter и Task выполняет команды из README
- **THEN** приложение становится доступно по `http://localhost:8080` без обращения к каким-либо внешним инструкциям

#### Scenario: IDE user starts the app
- **WHEN** разработчик запускает конфигурацию `main.dart` в GoLand/IntelliJ по README
- **THEN** README предупреждает, что браузер автоматически не открывается и нужно самому открыть адрес dev-сервера

### Requirement: Verification instructions in README

README SHALL документировать локальную проверку: команды `task lint` и `task test` (эквивалентно `flutter analyze` и `flutter test`) и автоматическую проверку каждого push и pull request в GitHub Actions.

#### Scenario: Contributor verifies changes
- **WHEN** разработчик перед отправкой изменений выполняет команды проверки из README
- **THEN** статический анализ и тесты запускаются локально, а README упоминает, что те же проверки выполняет CI

### Requirement: Deployment instructions in README

README SHALL документировать развёртывание: release-сборку `flutter build web --release`, назначение статического каталога `build/web` и размещение его содержимого на произвольном статическом хостинге, а также локальную проверку сборки статическим сервером (например, `python3 -m http.server 8080 --directory build/web`). README SHALL явно указывать, что специфичный хостинг в проекте не настроен и выбор хостинга остаётся за администратором.

#### Scenario: Operator deploys from README alone
- **WHEN** оператор выполняет release-сборку и размещает её на статическом хостинге по README
- **THEN** приложение работает по HTTP без серверной части, и README не обещает настроенного в проекте хостинга

#### Scenario: Operator verifies the build locally
- **WHEN** оператор перед публикацией запускает локальный статический сервер из README поверх `build/web`
- **THEN** приложение доступно по `http://localhost:8080` и работает в release-режиме

### Requirement: No RTK mentions in README

README SHALL NOT содержать упоминаний RTK: все команды SHALL быть записаны через задачи Taskfile или прямые команды `flutter`/`dart`, работающие без RTK.

#### Scenario: Reader follows commands without RTK
- **WHEN** читатель выполняет любую команду из README в окружении без RTK
- **THEN** команда работает без установки или знания RTK, а слово «rtk» в README не встречается

### Requirement: No manual verification log in README

README SHALL NOT содержать раздел «Результаты проверки» и иной журнал одноразовых ручных проверок с датами: результаты проверок относятся к процессу разработки, а не к постоянной документации. Проверяемые утверждения о доступности и корректности SHALL выражаться требованиями и CI, а не журналом.

#### Scenario: README contains no dated check log
- **WHEN** читатель просматривает README
- **THEN** в нём нет раздела с результатами ручных проверок, датированных конкретным днём
