import 'dart:async';

import 'package:currency/theme_location.dart';

import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:currency/currency_page.dart';
import 'package:currency/exchange_rates.dart';
import 'package:currency/main.dart';
import 'package:currency/rate_table_preferences.dart';
import 'package:currency/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('единая форма имеет заданный порядок на широком экране', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );
    final ordered = [
      'amount-field',
      'rate-row-USD',
      'rate-row-CZK',
      'rate-row-GBP',
      'add-target-menu',
    ];
    for (var i = 1; i < ordered.length; i++) {
      expect(
        tester.getRect(find.byKey(Key(ordered[i - 1]))).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(Key(ordered[i]))).top),
      );
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('amount-field')))
          .controller!
          .text,
      '1',
    );
    for (final key in [
      'base-menu',
      'from-menu',
      'to-menu',
      'swap-currencies-button',
      'conversion-result',
    ]) {
      expect(find.byKey(Key(key)), findsNothing);
    }
    await tester.enterText(
      find.byKey(const Key('amount-field')),
      '1000000000000',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Конвертер'), findsNothing);
    expect(find.text('Курсы относительно'), findsNothing);
    for (final label in ['Валюта', 'Курс', 'EUR → валюта', 'Валюта → EUR']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.byKey(const Key('conversion-result-USD'))).dx,
      tester.getTopLeft(find.byKey(const Key('conversion-result-CZK'))).dx,
    );
  });

  testWidgets('пустая, неверная и нулевая сумма обновляют все строки', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      preferencesStore: _FakePreferencesStore(
        value: const RateTablePreferences(
          base: 'EUR',
          targets: ['EUR', 'JPY', 'KWD'],
        ),
      ),
    );
    for (final (input, status) in [
      ('', 'Введите сумму'),
      ('3,000.50', 'Исправьте сумму'),
    ]) {
      await tester.enterText(find.byKey(const Key('amount-field')), input);
      await tester.pump();
      for (final code in ['EUR', 'JPY', 'KWD']) {
        expect(_text(tester, Key('conversion-result-$code')), status);
        expect(_text(tester, Key('reverse-result-$code')), status);
      }
      expect(
        find.text(
          'Одна сумма для обоих направлений: из EUR в валюту строки и обратно',
        ),
        findsOneWidget,
      );
      expect(find.text('1 EUR = 160,0000 JPY'), findsOneWidget);
      expect(find.textContaining('За 4 сентября'), findsNWidgets(2));
    }
    await tester.enterText(find.byKey(const Key('amount-field')), '0');
    await tester.pump();
    for (final (code, expected) in [
      ('EUR', '0,00 EUR'),
      ('JPY', '0 JPY'),
      ('KWD', '0,000 KWD'),
    ]) {
      expect(_text(tester, Key('conversion-result-$code')), expected);
      expect(_text(tester, Key('reverse-result-$code')), '0,00 EUR');
    }
    await tester.enterText(find.byKey(const Key('amount-field')), '12,3456');
    await tester.pump();
    expect(_text(tester, const Key('conversion-result-EUR')), '12,35 EUR');
    expect(_text(tester, const Key('conversion-result-JPY')), '1 975 JPY');
    expect(_text(tester, const Key('conversion-result-KWD')), '4,074 KWD');
    expect(_text(tester, const Key('reverse-result-EUR')), '12,35 EUR');
    expect(_text(tester, const Key('reverse-result-JPY')), '0,08 EUR');
    expect(_text(tester, const Key('reverse-result-KWD')), '37,41 EUR');
  });

  testWidgets('неконечный результат показывает ошибку только своей строки', (
    tester,
  ) async {
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      return http.Response(
        jsonEncode([
          {'base': 'EUR', 'quote': 'USD', 'rate': 1e300, 'date': '2026-09-04'},
          {'base': 'EUR', 'quote': 'CZK', 'rate': 25, 'date': '2026-09-04'},
          {'base': 'EUR', 'quote': 'GBP', 'rate': 1e-300, 'date': '2026-09-04'},
        ]),
        200,
      );
    });
    await tester.enterText(
      find.byKey(const Key('amount-field')),
      '1000000000000',
    );
    await tester.pump();
    expect(
      _text(tester, const Key('conversion-result-USD')),
      'Не удалось рассчитать сумму.',
    );
    expect(
      _text(tester, const Key('conversion-result-CZK')),
      '25 000 000 000 000,00 CZK',
    );
    expect(_text(tester, const Key('reverse-result-USD')), '0,00 EUR');
    expect(_text(tester, const Key('conversion-result-GBP')), '0,00 GBP');
    expect(
      _text(tester, const Key('reverse-result-GBP')),
      'Не удалось рассчитать сумму.',
    );
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('добавление считает текущую сумму и сообщает о полном каталоге', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );
    await tester.enterText(find.byKey(const Key('amount-field')), '10');
    for (final label in [
      'EUR · Euro',
      'JPY · Japanese Yen',
      'KWD · Kuwaiti Dinar',
    ]) {
      await _choose(tester, const Key('add-target-menu'), label);
      await tester.pumpAndSettle();
      expect(_menuText(tester, const Key('add-target-menu')), isEmpty);
    }
    expect(_text(tester, const Key('conversion-result-JPY')), '1 600 JPY');
    expect(find.text('Все валюты уже добавлены.'), findsOneWidget);
    final menu = tester.widget<DropdownMenu<String>>(
      find.byKey(const Key('add-target-menu')),
    );
    expect(menu.dropdownMenuEntries.every((entry) => !entry.enabled), isTrue);
    expect(
      tester
          .widgetList<RateRow>(find.byType(RateRow))
          .map((row) => row.currency.code),
      ['USD', 'CZK', 'GBP', 'EUR', 'JPY', 'KWD'],
    );
  });

  testWidgets('возврат списка принимает только последний запрос', (
    tester,
  ) async {
    final oldEur = Completer<http.Response>();
    final withJpy = Completer<http.Response>();
    var calls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      expectSync(request.url.queryParameters['base'], 'EUR');
      if (++calls == 1) return oldEur.future;
      if (request.url.queryParameters['quotes']!.contains('JPY')) {
        return withJpy.future;
      }
      return _rates(request);
    }, settle: false);
    await tester.pump();
    await tester.pump();
    for (final direction in ['conversion', 'reverse']) {
      expect(_text(tester, Key('$direction-result-CZK')), 'Загрузка курса…');
    }
    expect(find.textContaining('За '), findsNothing);
    await _choose(tester, const Key('add-target-menu'), 'JPY · Japanese Yen');
    await tester.ensureVisible(find.byKey(const Key('remove-JPY')));
    await tester.tap(find.byKey(const Key('remove-JPY')));
    await tester.pumpAndSettle();
    withJpy.complete(
      _ratesFor('EUR', ['USD', 'CZK', 'GBP', 'JPY'], rateOverride: 99),
    );
    oldEur.complete(_ratesFor('EUR', ['USD', 'CZK', 'GBP'], rateOverride: 99));
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('conversion-result-CZK')), '25,00 CZK');
    expect(_text(tester, const Key('reverse-result-CZK')), '0,04 EUR');
    expect(find.byKey(const Key('rate-row-JPY')), findsNothing);
    expect(calls, 3);
  });

  testWidgets(
    'ошибка курсов сохраняет строки, тождественный результат и повтор',
    (tester) async {
      var attempts = 0;
      await _pump(
        tester,
        (request) async {
          if (request.url.path.endsWith('/currencies')) return _catalog();
          if (++attempts == 1) return http.Response('unavailable', 503);
          return _ratesFor('EUR', ['CZK']);
        },
        preferencesStore: _FakePreferencesStore(
          value: const RateTablePreferences(
            base: 'USD',
            targets: ['EUR', 'CZK', 'GBP'],
          ),
        ),
      );
      expect(find.byType(RateRow), findsNWidgets(3));
      expect(_text(tester, const Key('conversion-result-EUR')), '1,00 EUR');
      expect(_text(tester, const Key('reverse-result-EUR')), '1,00 EUR');
      expect(_text(tester, const Key('reverse-result-CZK')), 'Курс недоступен');
      expect(
        _text(tester, const Key('conversion-result-CZK')),
        'Курс недоступен',
      );
      expect(find.byKey(const Key('add-target-menu')), findsOneWidget);
      await tester.ensureVisible(find.text('Повторить'));
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(_text(tester, const Key('conversion-result-CZK')), '25,00 CZK');
      expect(
        _text(tester, const Key('conversion-result-GBP')),
        'Курс недоступен',
      );
      expect(_text(tester, const Key('reverse-result-CZK')), '0,04 EUR');
      expect(_text(tester, const Key('reverse-result-GBP')), 'Курс недоступен');
      expect(find.byKey(const Key('remove-GBP')), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets('неудачное обновление использует текущую сумму и прежнюю дату', (
    tester,
  ) async {
    final refresh = Completer<http.Response>();
    var calls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      if (++calls == 2) return refresh.future;
      return _rates(request);
    });
    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('amount-field')), '10');
    await tester.pump();
    refresh.complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('conversion-result-CZK')), '250,00 CZK');
    expect(_text(tester, const Key('reverse-result-CZK')), '0,40 EUR');
    expect(find.textContaining('За 4 сентября'), findsNWidgets(3));
    expect(find.textContaining('Показаны предыдущие курсы'), findsOneWidget);
  });

  testWidgets('фокус следует форме, а результаты не забирают его', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );
    final amount = find.byKey(const Key('amount-field'));
    await tester.tap(amount);
    final focus = FocusManager.instance.primaryFocus;
    await tester.enterText(amount, '12');
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('remove-USD')))
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );
    for (final code in ['CZK', 'GBP']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(Key('remove-$code')))
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('add-target-menu')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
      reason: FocusManager.instance.primaryFocus.toString(),
    );
    semantics.dispose();
  });

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

      expect(_text(tester, const Key('conversion-result-CZK')), contains('75'));
      expect(
        _text(tester, const Key('conversion-result-CZK')),
        contains('CZK'),
      );
      expect(_text(tester, const Key('conversion-result-USD')), '3 600,00 USD');
      expect(
        _text(tester, const Key('conversion-result-CZK')),
        '75 000,00 CZK',
      );
      expect(_text(tester, const Key('conversion-result-GBP')), '2 400,00 GBP');
      expect(find.text('1 EUR = 25,0000 CZK'), findsOneWidget);
      expect(_text(tester, const Key('reverse-result-USD')), '2 500,00 EUR');
      expect(_text(tester, const Key('reverse-result-CZK')), '120,00 EUR');
      expect(_text(tester, const Key('reverse-result-GBP')), '3 750,00 EUR');
      await tester.enterText(amountField, '100');
      await tester.pump();
      expect(_text(tester, const Key('conversion-result-CZK')), '2 500,00 CZK');
      expect(_text(tester, const Key('reverse-result-CZK')), '4,00 EUR');
      expect(callsBeforeTyping, 1);
      expect(rateCalls, callsBeforeTyping);
      expect(find.textContaining('За 4 сентября'), findsNWidgets(3));
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
    expect(
      _text(tester, const Key('conversion-result-CZK')),
      'Исправьте сумму',
    );
  });

  testWidgets('удаляет все цели и восстанавливает пустой список без запросов', (
    tester,
  ) async {
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
    expect(find.byType(RateRow), findsNothing);
    expect(find.byKey(const Key('amount-field')), findsOneWidget);
    expect(find.byKey(const Key('add-target-menu')), findsOneWidget);
    expect(store.value?.targets, isEmpty);

    store.value = const RateTablePreferences(base: 'GBP', targets: []);
    rateCalls = 0;
    await _pump(tester, handler, preferencesStore: store);
    expect(find.byKey(const Key('empty-rates')), findsOneWidget);
    expect(store.value?.base, 'EUR');
    expect(rateCalls, 0);
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

  testWidgets('список только из базы рассчитывается без запроса курса', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async {
        if (request.url.path.endsWith('/currencies')) return _catalog();
        fail('Тождественный курс не требует запроса');
      },
      preferencesStore: _FakePreferencesStore(
        value: const RateTablePreferences(base: 'EUR', targets: ['EUR']),
      ),
    );
    await tester.enterText(find.byKey(const Key('amount-field')), '3000');
    await tester.pump();
    expect(_text(tester, const Key('conversion-result-EUR')), '3 000,00 EUR');
    expect(_text(tester, const Key('reverse-result-EUR')), '3 000,00 EUR');
    expect(find.text('Тождественный курс'), findsOneWidget);
    expect(find.textContaining('За '), findsNothing);
    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();
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
    expect(store.value?.base, 'EUR');
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
    expect(store.value?.base, 'EUR');
    expect(store.value?.targets, ['JPY']);
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);

    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) {
        return http.Response('[{"iso_code":"CHF","name":"Swiss Franc"}]', 200);
      }
      expectSync(request.url.queryParameters['base'], 'EUR');
      return _ratesFor('EUR', ['CHF'], rateOverride: 0.9);
    });
    expect(find.byKey(const Key('base-menu')), findsNothing);
    expect(find.byKey(const Key('empty-rates')), findsOneWidget);
    await _choose(tester, const Key('add-target-menu'), 'CHF · Swiss Franc');
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('conversion-result-CHF')), '0,90 CHF');
  });

  testWidgets('неудачное обновление сохраняет прежние значения', (
    tester,
  ) async {
    var failRates = false;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/currencies')) return _catalog();
      return failRates ? http.Response('{}', 503) : _rates(request);
    });
    final before = _text(tester, const Key('conversion-result-CZK'));
    final reverseBefore = _text(tester, const Key('reverse-result-CZK'));
    failRates = true;

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(_text(tester, const Key('conversion-result-CZK')), before);
    expect(_text(tester, const Key('reverse-result-CZK')), reverseBefore);
    expect(find.textContaining('Показаны предыдущие курсы'), findsOneWidget);
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
      (uri) => uri.queryParameters['base'] == 'EUR',
    );
    expect(tableRequest.queryParameters['quotes'], 'JPY,USD');
    expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-USD')), findsOneWidget);
    expect(find.byKey(const Key('rate-row-GBP')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('rate-row-JPY'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('rate-row-USD'))).dy),
    );
    expect(rateRequests.length, 1);
    expect(_text(tester, const Key('conversion-result-JPY')), '160 JPY');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('amount-field')))
          .controller!
          .text,
      '1',
    );
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
      var failRates = true;
      Future<http.Response> handler(http.Request request) async {
        if (request.url.path.endsWith('/currencies')) return _catalog();
        if (failRates) {
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

      expect(find.textContaining('ошибку 503'), findsOneWidget);
      expect(store.value?.base, 'EUR');
      expect(store.value?.targets, ['USD', 'CZK', 'JPY']);

      failRates = false;
      await _pump(tester, handler, preferencesStore: store);
      expect(find.byKey(const Key('rate-row-GBP')), findsNothing);
      expect(find.byKey(const Key('rate-row-JPY')), findsOneWidget);
      expect(find.textContaining('1 EUR ='), findsWidgets);
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
    await _choose(tester, const Key('add-target-menu'), 'JPY · Japanese Yen');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount-field')), '100');
    await tester.pump();
    expect(_text(tester, const Key('conversion-result-JPY')), '16 000 JPY');
    expect(_text(tester, const Key('reverse-result-JPY')), '0,63 EUR');
    semantics.dispose();
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
    expect(find.byKey(const Key('conversion-result-KWD')), findsNothing);
    expect(find.byKey(const Key('reverse-result-KWD')), findsNothing);
    expect(_text(tester, const Key('reverse-result-CZK')), '0,04 EUR');
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
    expect(find.byKey(const Key('base-menu')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('amount-field')),
      '1000000000000',
    );
    await tester.pumpAndSettle();
    expect(
      _text(tester, const Key('conversion-result-CZK')),
      '25 000 000 000 000,00 CZK',
    );
    expect(find.text('EUR → CZK'), findsOneWidget);
    expect(find.text('CZK → EUR'), findsOneWidget);
    expect(
      _text(tester, const Key('reverse-result-CZK')),
      '40 000 000 000,00 EUR',
    );
    for (final key in [
      'amount-field',
      'conversion-result-CZK',
      'reverse-result-CZK',
      'remove-CZK',
      'add-target-menu',
    ]) {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    final size = tester.getSize(find.byKey(const Key('remove-CZK')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
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
    final result = find.byKey(const Key('conversion-result-CZK'));
    await tester.ensureVisible(result);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(result).getSemanticsData().label,
      contains('Результат конвертации EUR → CZK'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('remove-CZK')))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );
    final reverse = find.byKey(const Key('reverse-result-CZK'));
    await tester.ensureVisible(reverse);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(reverse).getSemanticsData().label,
      contains('Результат конвертации CZK → EUR'),
    );
    expect(data.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
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

  testWidgets('шапка компактная: иконки рядом с заголовком, подзаголовка нет', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
    );

    final titleRect = tester.getRect(find.text('Курсы валют'));
    final refreshRect = tester.getRect(find.byKey(const Key('refresh-button')));
    final toggleRect = tester.getRect(
      find.byKey(const Key('theme-toggle-button')),
    );
    expect(refreshRect.left, greaterThan(titleRect.right));
    expect(refreshRect.top, lessThan(titleRect.bottom));
    expect(toggleRect.left, greaterThan(refreshRect.right));
    expect(toggleRect.top, lessThan(titleRect.bottom));
    expect(
      find.text(
        'Сравнивайте ежедневные справочные курсы и пересчитывайте суммы.',
      ),
      findsNothing,
    );
    final refresh = tester.widget<IconButton>(
      find.byKey(const Key('refresh-button')),
    );
    expect(refresh.tooltip, 'Обновить');
    expect(
      find.textContaining('Обновить'),
      findsNothing,
      reason: 'У кнопки обновления не должно быть видимой надписи',
    );
  });

  testWidgets('переключатель темы меняет тему и запоминает выбор', (
    tester,
  ) async {
    final themeStore = _FakeThemeStore();
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      themeStore: themeStore,
    );

    final toggle = find.byKey(const Key('theme-toggle-button'));
    final materialApp = find.byType(MaterialApp);
    expect(tester.widget<MaterialApp>(materialApp).themeMode, ThemeMode.system);
    expect(tester.widget<IconButton>(toggle).tooltip, 'Тема: Авто, светлая');

    await _selectTheme(tester, 'dark');
    expect(tester.widget<MaterialApp>(materialApp).themeMode, ThemeMode.dark);
    expect(tester.widget<IconButton>(toggle).tooltip, 'Тема: Тёмная');
    expect(themeStore.writes, 1);
    expect(themeStore.initial, ThemePreference.dark);

    await _selectTheme(tester, 'light');
    expect(tester.widget<MaterialApp>(materialApp).themeMode, ThemeMode.light);
    expect(themeStore.writes, 2);
    expect(themeStore.initial, ThemePreference.light);
  });

  testWidgets('сохранённая тёмная тема восстанавливается при запуске', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      themeStore: _FakeThemeStore(initial: ThemePreference.dark),
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('theme-toggle-button')))
          .tooltip,
      'Тема: Тёмная',
    );
  });

  testWidgets('ошибка записи темы не мешает переключению', (tester) async {
    await _pump(
      tester,
      (request) async => request.url.path.endsWith('/currencies')
          ? _catalog()
          : _rates(request),
      themeStore: _FakeThemeStore(throwOnWrite: true),
    );

    await _selectTheme(tester, 'dark');

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'автоматика сохраняет данные и фокус при восходе, закате и смене часов',
    (tester) async {
      var now = DateTime.utc(1994, 1, 2, 7, 7);
      var requests = 0;
      var positions = 0;
      final store = _FakeThemeStore();
      await _pump(
        tester,
        (request) async {
          requests++;
          return request.url.path.endsWith('/currencies')
              ? _catalog()
              : _rates(request);
        },
        themeStore: store,
        clock: () => now,
        locationProvider: () async {
          positions++;
          return (latitude: 35.0, longitude: 0.0);
        },
      );
      ThemeMode? mode() =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;
      expect(mode(), ThemeMode.dark);
      await tester.enterText(find.byKey(const Key('amount-field')), '123');
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('amount-field')),
      );
      final editable = find.descendant(
        of: find.byKey(const Key('amount-field')),
        matching: find.byType(EditableText),
      );
      final focus = tester.widget<EditableText>(editable).focusNode;
      final result = _text(tester, const Key('conversion-result-CZK'));
      final rows = tester
          .widgetList(find.byKey(const Key('rate-row-USD')))
          .length;
      final before = requests;
      for (final (instant, expected) in [
        (DateTime.utc(1994, 1, 2, 7, 10), ThemeMode.light),
        (DateTime.utc(1994, 1, 2, 17, 1), ThemeMode.dark),
        (DateTime.utc(1994, 1, 3, 12), ThemeMode.light),
        (DateTime.utc(1994, 1, 2), ThemeMode.dark),
      ]) {
        now = instant;
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(mode(), expected);
        expect(field.controller!.text, '123');
        expect(focus.hasFocus, isTrue);
        expect(_text(tester, const Key('conversion-result-CZK')), result);
        expect(
          tester.widgetList(find.byKey(const Key('rate-row-USD'))).length,
          rows,
        );
        expect(requests, before);
        expect(store.writes, 0);
        expect(positions, 1);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(positions, 1);
    },
  );

  testWidgets(
    'возврат пересчитывает сразу и обновляет координаты без перекрытия',
    (tester) async {
      var now = DateTime.utc(2026, 9, 6, 12);
      final refresh = Completer<ThemeLocation?>();
      var calls = 0;
      await _pump(
        tester,
        (r) async =>
            r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
        clock: () => now,
        locationProvider: () {
          calls++;
          return calls == 1
              ? Future.value((latitude: 0.0, longitude: 0.0))
              : refresh.future;
        },
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = DateTime.utc(2026, 9, 7);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(calls, 2);
      refresh.complete(null);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    },
  );

  testWidgets('ошибки координат следуют системе до явного повтора Авто', (
    tester,
  ) async {
    for (final result in <Future<ThemeLocation?> Function()>[
      () async => null,
      () async => throw StateError('denied'),
      () async => (latitude: double.nan, longitude: 0.0),
      () => Completer<ThemeLocation?>().future,
    ]) {
      var calls = 0;
      final store = _FakeThemeStore(throwOnRead: true);
      await _pump(
        tester,
        (r) async =>
            r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
        themeStore: store,
        locationProvider: () {
          calls++;
          return result();
        },
      );
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('theme-toggle-button')))
            .tooltip,
        'Тема: Авто, тёмная',
      );
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pump(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(store.writes, 0);
      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Местоположение недоступно — используется системная тема'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('theme-auto')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(store.initial, ThemePreference.auto);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'ручной режим игнорирует поздние координаты и не запрашивает новые',
    (tester) async {
      for (final preference in [ThemePreference.light, ThemePreference.dark]) {
        var calls = 0;
        final pending = Completer<ThemeLocation?>();
        await _pump(
          tester,
          (r) async =>
              r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
          locationProvider: () {
            calls++;
            return pending.future;
          },
        );
        await _selectTheme(tester, preference.name);
        pending.complete((latitude: 0.0, longitude: 0.0));
        await tester.pumpAndSettle();
        final expected = preference == ThemePreference.light
            ? ThemeMode.light
            : ThemeMode.dark;
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          expected,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(minutes: 2));
        expect(calls, 1);
        await _pump(
          tester,
          (r) async =>
              r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
          themeStore: _FakeThemeStore(initial: preference),
          locationProvider: () async {
            calls++;
            return null;
          },
        );
        expect(calls, 1);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          expected,
        );
      }
    },
  );

  testWidgets(
    'меню закрывается без записи, работает с клавиатурой и возвращает фокус',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = _FakeThemeStore();
      await _pump(
        tester,
        (r) async =>
            r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
        themeStore: store,
      );
      final toggle = find.byKey(const Key('theme-toggle-button'));
      final button = tester.widget<IconButton>(toggle);
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme-auto')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(button.focusNode!.hasFocus, isTrue);
      expect(store.writes, 0);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      expect(find.byKey(const Key('theme-auto')), findsNothing);
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.initial, ThemePreference.light);
      expect(button.focusNode!.hasFocus, isTrue);
      expect(
        tester.getSemantics(toggle).getSemanticsData().tooltip,
        'Тема: Светлая',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'после повторного Авто ручной выбор доступен во время и после геолокации',
    (tester) async {
      final store = _FakeThemeStore(initial: ThemePreference.light);
      var pending = Completer<ThemeLocation?>();
      await _pump(
        tester,
        (r) async =>
            r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
        themeStore: store,
        clock: () => DateTime.utc(2026, 9, 6, 12),
        locationProvider: () => pending.future,
      );
      for (final manual in ['light', 'dark']) {
        await _selectTheme(tester, 'auto');
        await tester.tap(find.byKey(const Key('theme-toggle-button')));
        await tester.pumpAndSettle();
        pending.complete((latitude: 0.0, longitude: 0.0));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('theme-$manual')));
        await tester.pumpAndSettle();
        expect(
          store.initial,
          manual == 'light' ? ThemePreference.light : ThemePreference.dark,
        );
        pending = Completer<ThemeLocation?>();
        await _selectTheme(tester, 'auto');
        await _selectTheme(tester, manual);
        pending.complete(null);
        await tester.pumpAndSettle();
        expect(
          store.initial,
          manual == 'light' ? ThemePreference.light : ThemePreference.dark,
        );
        pending = Completer<ThemeLocation?>();
      }
    },
  );

  testWidgets('меню и шапка помещаются при 375 пикселях и увеличенном тексте', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final mode in [
      ThemePreference.light,
      ThemePreference.dark,
      ThemePreference.auto,
    ]) {
      await _pump(
        tester,
        (r) async =>
            r.url.path.endsWith('/currencies') ? _catalog() : _rates(r),
        textScale: 2,
        themeStore: _FakeThemeStore(initial: mode),
      );
      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();
      for (final name in ['auto', 'light', 'dark']) {
        final rect = tester.getRect(find.byKey(Key('theme-$name')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(375));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool settle = true,
  double textScale = 1,
  RateTablePreferencesStore? preferencesStore,
  ThemePreferenceStore? themeStore,
  DateTime Function()? clock,
  Future<ThemeLocation?> Function()? locationProvider,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = CurrencyApp(
    key: UniqueKey(),
    api: ExchangeRatesApi(client: MockClient(handler)),
    preferencesStore: preferencesStore,
    themeStore: themeStore,
    clock: clock,
    locationProvider: locationProvider,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
  await tester.pumpWidget(app);
  if (settle) await tester.pumpAndSettle();
}

class _FakeThemeStore implements ThemePreferenceStore {
  _FakeThemeStore({
    this.initial,
    this.throwOnWrite = false,
    this.throwOnRead = false,
  });

  ThemePreference? initial;
  final bool throwOnWrite;
  final bool throwOnRead;
  int writes = 0;

  @override
  ThemePreference? read() {
    if (throwOnRead) throw StateError("read failed");
    return initial;
  }

  @override
  void write(ThemePreference mode) {
    if (throwOnWrite) throw StateError('write failed');
    writes++;
    initial = mode;
  }
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

Future<void> _selectTheme(WidgetTester tester, String mode) async {
  await tester.tap(find.byKey(const Key('theme-toggle-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('theme-$mode')));
  await tester.pumpAndSettle();
}
