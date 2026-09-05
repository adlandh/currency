import 'dart:async';
import 'dart:convert';

import 'package:currency/currency_page.dart';
import 'package:currency/exchange_rates.dart';
import 'package:currency/main.dart';
import 'package:currency/rate_table_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'показывает начальные курсы и пересчитывает сумму без нового запроса',
    (tester) async {
      var rateCalls = 0;
      await _pump(tester, (request) async {
        if (request.url.path.endsWith('/currencies')) return _catalog();
        rateCalls++;
        return _rates(request);
      });

      expect(find.text('Курсы валют'), findsOneWidget);
      expect(find.byKey(const Key('rate-row-USD')), findsOneWidget);
      expect(find.byKey(const Key('rate-row-CZK')), findsOneWidget);
      expect(find.byKey(const Key('rate-row-GBP')), findsOneWidget);
      final callsBeforeTyping = rateCalls;

      final amountField = find.byKey(const Key('amount-field'));
      await tester.tap(amountField);
      final editable = find.descendant(
        of: amountField,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      final inputTheme = Theme.of(tester.element(amountField))
          .inputDecorationTheme;
      final focused = inputTheme.focusedBorder! as OutlineInputBorder;
      final enabled = inputTheme.enabledBorder! as OutlineInputBorder;
      expect(focused.borderSide.width, greaterThan(enabled.borderSide.width));

      await tester.enterText(amountField, '3 000');
      await tester.pump();

      expect(_text(tester, const Key('conversion-result')), contains('75'));
      expect(_text(tester, const Key('conversion-result')), contains('CZK'));
      expect(rateCalls, callsBeforeTyping);
      expect(find.textContaining('Курс за'), findsOneWidget);
      expect(find.textContaining('Источник: Frankfurter'), findsOneWidget);
    },
  );

  testWidgets('ошибка суммы скрывает предыдущий результат', (tester) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );

    await tester.enterText(find.byKey(const Key('amount-field')), '3,000.50');
    await tester.pump();

    expect(find.text('Введите число, например 3 000,50.'), findsOneWidget);
    expect(_text(tester, const Key('conversion-result')), 'Исправьте сумму');
  });

  testWidgets('удаляет все цели, не затрагивая конвертер', (tester) async {
    final store = _FakePreferencesStore();
    var rateCalls = 0;
    Future<http.Response> handler(http.Request request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      rateCalls++;
      return _rates(request);
    }

    await _pump(tester, handler, preferencesStore: store);

    for (final code in ['USD', 'CZK', 'GBP']) {
      final button = find.byKey(Key('remove-$code'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
    }

    expect(find.byKey(const Key('empty-rates')), findsOneWidget);
    expect(find.byKey(const Key('conversion-result')), findsOneWidget);
    expect(store.value?.targets, isEmpty);

    rateCalls = 0;
    await _pump(tester, handler, preferencesStore: store);
    expect(find.byKey(const Key('empty-rates')), findsOneWidget);
    expect(rateCalls, 1, reason: 'После восстановления нужен только конвертер');
  });

  testWidgets('добавляет валюту один раз', (tester) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );

    await _choose(tester, const Key('add-target-menu'), 'JPY · Japanese Yen');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);

    await _choose(tester, const Key('add-target-menu'), 'JPY · Japanese Yen');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
  });

  testWidgets('смена базы не меняет пару конвертера', (tester) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );

    await _choose(tester, const Key('base-menu'), 'USD · US Dollar');
    await tester.pumpAndSettle();

    expect(find.textContaining('1 USD ='), findsWidgets);
    expect(_text(tester, const Key('conversion-rate')), contains('1 EUR ='));
  });

  testWidgets('совпадающая пара не делает запрос курса', (tester) async {
    var rateCalls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      rateCalls++;
      return _rates(request);
    });
    final before = rateCalls;

    await _choose(tester, const Key('to-menu'), 'EUR · Euro');
    await tester.pumpAndSettle();

    expect(rateCalls, before);
    expect(_text(tester, const Key('conversion-result')), contains('1,00 EUR'));
  });

  testWidgets('показывает ошибку каталога и повторяет загрузку', (
    tester,
  ) async {
    final store = _FakePreferencesStore(
      value: const RateTablePreferences(base: 'CZK', targets: ['JPY']),
    );
    var calls = 0;
    await _pump(
      tester,
      (request) async {
        if (request.url.path.endsWith('/currencies')) {
          calls++;
          return calls == 1 ? http.Response('{}', 503) : _catalog();
        }
        return _rates(request);
      },
      settle: false,
      preferencesStore: store,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ошибку 503'), findsOneWidget);
    expect(store.writes, 0);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('amount-field')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-USD')), findsNothing);
    expect(store.value?.base, 'CZK');
  });

  testWidgets('обрабатывает пустой каталог и отсутствие начальных валют', (
    tester,
  ) async {
    final store = _FakePreferencesStore(
      value: const RateTablePreferences(base: 'CZK', targets: ['JPY']),
    );
    var catalogCalls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) {
        catalogCalls++;
        return catalogCalls == 1 ? http.Response('[]', 200) : _catalog();
      }
      return _rates(request);
    }, preferencesStore: store);
    expect(find.text('Источник не вернул доступные валюты.'), findsOneWidget);
    expect(store.writes, 0);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(store.value?.base, 'CZK');
    expect(store.value?.targets, ['JPY']);
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);

    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) {
        return http.Response('[{"iso_code":"CHF","name":"Swiss Franc"}]', 200);
      }
      fail('Для единственной совпадающей валюты запрос не нужен');
    });
    expect(_text(tester, const Key('conversion-result')), contains('CHF'));
  });

  testWidgets('неудачное обновление сохраняет прежние значения', (
    tester,
  ) async {
    var failRates = false;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      return failRates ? http.Response('{}', 503) : _rates(request);
    });
    final before = _text(tester, const Key('conversion-result'));
    failRates = true;

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(_text(tester, const Key('conversion-result')), before);
    expect(find.textContaining('Показан предыдущий курс'), findsOneWidget);
    expect(find.textContaining('Показаны предыдущие курсы'), findsOneWidget);
  });

  testWidgets('поздний ответ старой базы не заменяет новый выбор', (
    tester,
  ) async {
    final delayedUsd = Completer<http.Response>();
    final store = _FakePreferencesStore();
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      if (request.url.queryParameters['base'] == 'USD') {
        return delayedUsd.future;
      }
      return _rates(request);
    }, preferencesStore: store);

    await _choose(tester, const Key('base-menu'), 'USD · US Dollar');
    await tester.pump();
    await _choose(tester, const Key('base-menu'), 'GBP · Pound Sterling');
    await tester.pumpAndSettle();
    delayedUsd.complete(_ratesFor('USD', ['CZK', 'GBP']));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 GBP ='), findsWidgets);
    expect(find.textContaining('1 USD ='), findsNothing);
    expect(store.value?.base, 'GBP');
  });

  testWidgets('первый запрос таблицы использует сохранённый выбор', (
    tester,
  ) async {
    final store = _FakePreferencesStore(
      value: const RateTablePreferences(base: 'CZK', targets: ['JPY', 'USD']),
    );
    final rateRequests = <Uri>[];

    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      rateRequests.add(request.url);
      return _rates(request);
    }, preferencesStore: store);

    final tableRequest = rateRequests.singleWhere(
      (uri) => uri.queryParameters['base'] == 'CZK',
    );
    expect(tableRequest.queryParameters['quotes'], 'JPY,USD');
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-USD')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-GBP')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('rate-row-JPY'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('rate-row-USD'))).dy),
    );
    expect(_text(tester, const Key('conversion-rate')), contains('1 EUR ='));
  });

  testWidgets('согласовывает сохранённые коды с каталогом', (tester) async {
    final store = _FakePreferencesStore(
      value: const RateTablePreferences(
        base: 'AUD',
        targets: ['JPY', 'USD', 'JPY', 'AUD'],
      ),
    );

    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      preferencesStore: store,
    );

    expect(store.value?.base, 'EUR');
    expect(store.value?.targets, ['JPY', 'USD']);
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-USD')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-AUD')), findsNothing);
  });

  testWidgets(
    'сохраняет изменения даже при ошибке курсов и восстанавливает их',
    (tester) async {
      final store = _FakePreferencesStore();
      var failUsd = true;
      Future<http.Response> handler(http.Request request) async {
        if (request.url.path.endsWith('/currencies')) return _catalog();
        if (failUsd && request.url.queryParameters['base'] == 'USD') {
          return http.Response('{}', 503);
        }
        return _rates(request);
      }

      await _pump(tester, handler, preferencesStore: store);
      await _choose(tester, const Key('add-target-menu'), 'JPY · Japanese Yen');
      await tester.pumpAndSettle();
      final remove = find.byKey(const Key('remove-GBP'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await _choose(tester, const Key('base-menu'), 'USD · US Dollar');
      await tester.pumpAndSettle();

      expect(find.textContaining('ошибку 503'), findsOneWidget);
      expect(store.value?.base, 'USD');
      expect(store.value?.targets, ['USD', 'CZK', 'JPY']);

      failUsd = false;
      await _pump(tester, handler, preferencesStore: store);
      expect(find.byKey(const Key('rate-row-GBP')), findsNothing);
      expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenu<String>>(find.byKey(const Key('base-menu')))
            .initialSelection,
        'USD',
      );
    },
  );

  testWidgets('остаётся рабочим при ошибках чтения и записи настроек', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final readFailure = _FakePreferencesStore(throwOnRead: true);
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      preferencesStore: readFailure,
    );
    expect(
      find.textContaining('Не удалось восстановить настройки'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('preferences-notice')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.byKey(const Key('rate-row-USD')), findsOneWidget);

    final writeFailure = _FakePreferencesStore(throwOnWrite: true);
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      preferencesStore: writeFailure,
    );
    expect(
      find.textContaining('Не удалось сохранить настройки'),
      findsOneWidget,
    );
    await _choose(tester, const Key('base-menu'), 'USD · US Dollar');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byKey(const Key('base-menu')))
          .initialSelection,
      'USD',
    );
    semantics.dispose();
  });

  testWidgets('поздний ответ старой пары не заменяет новый выбор', (
    tester,
  ) async {
    final delayedGbp = Completer<http.Response>();
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      if (request.url.queryParameters['base'] == 'EUR' &&
          request.url.queryParameters['quotes'] == 'GBP') {
        return delayedGbp.future;
      }
      return _rates(request);
    });

    await _choose(tester, const Key('to-menu'), 'GBP · Pound Sterling');
    await _choose(tester, const Key('to-menu'), 'USD · US Dollar');
    await tester.pumpAndSettle();
    delayedGbp.complete(_ratesFor('EUR', ['GBP'], rateOverride: 99));
    await tester.pumpAndSettle();

    expect(_text(tester, const Key('conversion-rate')), contains('1,2000 USD'));
    expect(_text(tester, const Key('conversion-rate')), isNot(contains('GBP')));
  });

  testWidgets('удалённая во время загрузки цель не возвращается', (
    tester,
  ) async {
    final delayedKwd = Completer<http.Response>();
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      if (request.url.queryParameters['quotes']!.split(',').contains('KWD')) {
        return delayedKwd.future;
      }
      return _rates(request);
    });

    await _choose(tester, const Key('add-target-menu'), 'KWD · Kuwaiti Dinar');
    final remove = find.byKey(const Key('remove-KWD'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    delayedKwd.complete(_ratesFor('EUR', ['USD', 'CZK', 'GBP', 'KWD']));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rate-row-KWD')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('не применяет ответ после закрытия экрана', (tester) async {
    final pending = Completer<http.Response>();
    final client = MockClient((request) {
      if (request.url.path.endsWith('/currencies')) {
        return Future.value(_catalog());
      }
      return pending.future;
    });
    await tester.pumpWidget(CurrencyApp(api: ExchangeRatesApi(client: client)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(_ratesFor('EUR', ['USD', 'CZK', 'GBP']));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('помещается на ширине 360 пикселей при крупном тексте', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('amount-field')), findsOneWidget);
    expect(find.byKey(const Key('base-menu')), findsOneWidget);
  });

  testWidgets('результат объявлен как обновляемая семантическая область', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );

    final data = tester
        .getSemantics(find.byKey(const Key('conversion-semantics')))
        .getSemanticsData();
    expect(data.label, contains('Результат конвертации'));
    expect(data.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  testWidgets('поиск валют конвертера очищает и восстанавливает выбор', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );
    final resultBeforeSearch = _text(tester, const Key('conversion-result'));

    for (final (key, label) in [
      (const Key('from-menu'), 'EUR · Euro'),
      (const Key('to-menu'), 'CZK · Czech Koruna'),
    ]) {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(_menuText(tester, key), isEmpty);
      await tester.enterText(_menuField(key), 'JPY');
      await tester.pumpAndSettle();
      expect(_text(tester, const Key('conversion-result')), resultBeforeSearch);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_menuText(tester, key), label);
      expect(_text(tester, const Key('conversion-result')), resultBeforeSearch);
    }

    await tester.tap(find.byKey(const Key('from-menu')));
    await tester.pumpAndSettle();
    await tester.enterText(_menuField(const Key('from-menu')), 'JPY');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_menuText(tester, const Key('from-menu')), 'EUR · Euro');

    await tester.tap(find.byKey(const Key('to-menu')));
    await tester.pumpAndSettle();
    await tester.enterText(_menuField(const Key('to-menu')), 'GBP');
    await tester.tap(find.text('Получится'));
    await tester.pumpAndSettle();
    expect(_menuText(tester, const Key('to-menu')), 'CZK · Czech Koruna');

    await tester.tap(find.byKey(const Key('to-menu')));
    await tester.pumpAndSettle();
    await tester.enterText(_menuField(const Key('to-menu')), 'GBP');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_menuText(tester, const Key('to-menu')), 'GBP · Pound Sterling');
    expect(_text(tester, const Key('conversion-rate')), contains('GBP'));
  });

  testWidgets('валюту можно найти и выбрать клавиатурой', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: CurrencyMenu(
              fieldKey: const Key('keyboard-menu'),
              label: 'Валюта',
              currencies: const [
                CurrencyInfo(code: 'EUR', name: 'Euro'),
                CurrencyInfo(code: 'JPY', name: 'Japanese Yen'),
              ],
              selectedCode: 'EUR',
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    final menu = find.byKey(const Key('keyboard-menu'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    final field = find.descendant(of: menu, matching: find.byType(TextField));
    final editable = find.descendant(
      of: menu,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(field, 'JPY');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selected, 'JPY');
  });
}

Future<void> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool settle = true,
  double textScale = 1,
  RateTablePreferencesStore? preferencesStore,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = CurrencyApp(
    key: UniqueKey(),
    api: ExchangeRatesApi(client: MockClient(handler)),
    preferencesStore: preferencesStore,
  );
  await tester.pumpWidget(app);
  if (settle) await tester.pumpAndSettle();
}

class _FakePreferencesStore implements RateTablePreferencesStore {
  _FakePreferencesStore({
    this.value,
    this.throwOnRead = false,
    this.throwOnWrite = false,
  });

  RateTablePreferences? value;
  final bool throwOnRead;
  final bool throwOnWrite;
  int writes = 0;

  @override
  RateTablePreferences? read() {
    if (throwOnRead) throw StateError('read failed');
    return value;
  }

  @override
  void write(RateTablePreferences preferences) {
    if (throwOnWrite) throw StateError('write failed');
    writes++;
    value = RateTablePreferences(
      base: preferences.base,
      targets: List<String>.of(preferences.targets),
    );
  }
}

Future<void> _choose(WidgetTester tester, Key key, String label) async {
  final menu = tester.widget<DropdownMenu<String>>(find.byKey(key));
  final entry = menu.dropdownMenuEntries.singleWhere(
    (entry) => entry.label == label,
  );
  menu.onSelected?.call(entry.value);
  await tester.pump();
}

String _text(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  return switch (widget) {
    SelectableText(:final data, :final textSpan) =>
      data ?? textSpan?.toPlainText() ?? '',
    Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText() ?? '',
    _ => fail('Ожидался текстовый виджет, получен ${widget.runtimeType}'),
  };
}

Finder _menuField(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));

String _menuText(WidgetTester tester, Key key) =>
    tester.widget<TextField>(_menuField(key)).controller!.text;

http.Response _catalog() => http.Response(
  jsonEncode([
    {'iso_code': 'EUR', 'name': 'Euro'},
    {'iso_code': 'CZK', 'name': 'Czech Koruna'},
    {'iso_code': 'USD', 'name': 'US Dollar'},
    {'iso_code': 'GBP', 'name': 'Pound Sterling'},
    {'iso_code': 'JPY', 'name': 'Japanese Yen'},
    {'iso_code': 'KWD', 'name': 'Kuwaiti Dinar'},
  ]),
  200,
);

http.Response _rates(http.Request request) {
  final base = request.url.queryParameters['base']!;
  final quotes = request.url.queryParameters['quotes']!.split(',');
  return _ratesFor(base, quotes);
}

http.Response _ratesFor(
  String base,
  List<String> quotes, {
  double? rateOverride,
}) {
  const eurRates = {
    'CZK': 25.0,
    'USD': 1.2,
    'GBP': 0.8,
    'JPY': 160.0,
    'KWD': 0.33,
  };
  final baseInEur = base == 'EUR' ? 1.0 : 1 / eurRates[base]!;
  final rows = [
    for (final quote in quotes)
      if (quote != base)
        {
          'date': '2026-09-04',
          'base': base,
          'quote': quote,
          'rate':
              rateOverride ??
              (quote == 'EUR' ? 1.0 : eurRates[quote]!) * baseInEur,
        },
  ];
  return http.Response(jsonEncode(rows), 200);
}
