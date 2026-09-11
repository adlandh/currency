import 'dart:async';
import 'dart:convert';

import 'package:currency/exchange_rates.dart';
import 'package:currency/observability.dart';
import 'package:currency/main.dart';
import 'package:currency/rate_table_preferences.dart';
import 'package:currency/theme_preference.dart';
import 'package:currency/solar_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class RecordingTransport implements Transport {
  final events = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    if (fail) throw StateError('transport unavailable');
    for (final item in envelope.items) {
      final data = jsonDecode(
        utf8.decode(await item.dataFactory()),
      ) as Map<String, dynamic>;
      if (data.containsKey('event_id')) events.add(data);
    }
    return envelope.header.eventId;
  }
}

class FailingPreferences implements RateTablePreferencesStore {
  @override
  RateTablePreferences? read() => throw StateError('private settings');
  @override
  void write(RateTablePreferences value) =>
      throw StateError('private settings');
}

class FailingTheme implements ThemePreferenceStore {
  @override
  ThemePreference? read() => throw StateError('private theme');
  @override
  void write(ThemePreference value) => throw StateError('private theme');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingTransport transport;

  Future<void> initialize({double rate = 1}) async {
    await Sentry.init((options) {
      configureObservability(options);
      options.dsn = 'https://public@example.com/1';
      options.tracesSampleRate = rate;
      options.release = 'currency@test';
      options.environment = 'test';
      options.transport = transport;
    });
  }

  setUp(() async {
    transport = RecordingTransport();
    await runWithObservability(() {}, dsn: '');
    await initialize();
  });
  tearDown(Sentry.close);

  test('DSN и доля трасс проверяются до запуска', () {
    for (final dsn in [
      '',
      'bad',
      'ftp://key@host/1',
      'https://host/1',
      'https://key@host/',
      'https://key@host/1?secret=1',
    ]) {
      expect(validSentryDsn(dsn), isFalse);
    }
    expect(validSentryDsn('https://public@host/prefix/123'), isTrue);
    for (final rate in ['-1', '2', 'NaN', 'Infinity', 'bad', '']) {
      expect(sentryTraceRate(rate), 0);
    }
    expect(sentryTraceRate('0'), 0);
    expect(sentryTraceRate('1'), 1);
    expect(sentryTraceRate('0.1'), 0.1);
  });

  test('запуск ровно один раз без DSN и при сбое инициализации', () async {
    for (final dsn in ['', 'bad', 'https://public@host/1']) {
      var starts = 0;
      var initializations = 0;
      await runWithObservability(
        () => starts++,
        dsn: dsn,
        initialize: (configure, {appRunner}) async {
          initializations++;
          throw StateError('init');
        },
      );
      expect(starts, 1);
      expect(initializations, validSentryDsn(dsn) ? 1 : 0);
    }
    var starts = 0;
    await runWithObservability(
      () => starts++,
      dsn: 'https://public@host/1',
      initialize: (configure, {appRunner}) async {
        await appRunner!();
        throw StateError('after start');
      },
    );
    expect(starts, 1);
  });

  test('API сохраняет причины, стек и отправляет ошибку один раз', () async {
    final original = StateError('sensitive amount 987654');
    for (final mode in ['network', 'http', 'json', 'timeout']) {
      transport.events.clear();
      final api = ExchangeRatesApi(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          switch (mode) {
            case 'network':
              throw http.ClientException('987654');
            case 'http':
              return http.Response('987654', 503);
            case 'json':
              return http.Response('987654 invalid json', 200);
            default:
              return Completer<http.Response>().future;
          }
        }),
      );
      await expectLater(
        api.fetchCurrencies(),
        throwsA(isA<ExchangeRatesException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final errors = transport.events
          .where((event) => event['type'] != 'transaction')
          .toList();
      expect(errors, hasLength(1), reason: mode);
      final event = errors.single;
      expect(event['tags']['operation'], 'currencies.load');
      expect(
        event['exception']['values'][0]['stacktrace']['frames'],
        isNotEmpty,
      );
      expect(jsonEncode(event), isNot(contains('987654')));
      final transaction = transport.events.singleWhere(
        (e) => e['type'] == 'transaction',
      );
      expect(transaction['contexts']['trace']['status'], 'internal_error');
      expect(
        event['contexts']['trace']['trace_id'],
        transaction['contexts']['trace']['trace_id'],
      );
    }
    final api = ExchangeRatesApi(
      client: MockClient((_) async => throw original),
    );
    await expectLater(api.fetchCurrencies(), throwsA(same(original)));
  });

  test('параллельные операции не смешивают контекст и завершаются', () async {
    final pending = Completer<http.Response>();
    final api = ExchangeRatesApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('currencies')) return pending.future;
        return http.Response('[]', 200);
      }),
    );
    final currencies = api.fetchCurrencies();
    await api.fetchRates('EUR', ['USD']);
    pending.complete(http.Response('bad', 500));
    await expectLater(currencies, throwsA(isA<ExchangeRatesException>()));
    await Future<void>.delayed(Duration.zero);
    final transactions = transport.events
        .where((e) => e['type'] == 'transaction')
        .toList();
    expect(transactions, hasLength(2));
    expect(
      transactions.map((e) => e['contexts']['trace']['span_id']).toSet(),
      hasLength(2),
    );
    final rates = transactions.singleWhere(
      (e) => e['transaction'] == 'rates.load',
    );
    expect(rates['contexts']['trace']['status'], 'ok');
    final error = transport.events.singleWhere((e) => e['exception'] != null);
    final catalog = transactions.singleWhere(
      (e) => e['transaction'] == 'currencies.load',
    );
    expect(
      error['contexts']['trace']['span_id'],
      catalog['contexts']['trace']['span_id'],
    );
    expect(
      error['contexts']['trace']['span_id'],
      isNot(rates['contexts']['trace']['span_id']),
    );
    expect(rates['start_timestamp'], isNotNull);
    expect(rates['timestamp'], isNotNull);
  });

  test('доля 0 сохраняет ошибки; пустые цели не создают транзакций', () async {
    await Sentry.close();
    await initialize(rate: 0);
    final api = ExchangeRatesApi(
      client: MockClient((_) async => http.Response('', 500)),
    );
    await api.fetchRates('EUR', []);
    await api.fetchRates('EUR', ['EUR']);
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, isEmpty);
    await expectLater(
      api.fetchCurrencies(),
      throwsA(isA<ExchangeRatesException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
    expect(transport.events.single['type'], isNot('transaction'));
  });

  test('очищается итоговый пакет, включая автоматические поля', () async {
    const secret = 'SENSITIVE_987654';
    await Sentry.captureEvent(
      SentryEvent(
        message: SentryMessage(secret),
        user: SentryUser(id: secret),
        request: SentryRequest(url: 'https://host/?$secret', data: secret),
        contexts: Contexts.fromJson({
          'location': {'latitude': secret},
        }),
        breadcrumbs: [Breadcrumb(message: secret)],
        exceptions: [
          SentryException(
            type: 'FormatException',
            value: secret,
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  fileName: 'main.dart?$secret',
                  absPath: 'https://host/main.dart#$secret',
                  function: 'load',
                  lineNo: 12,
                  vars: {'amount': secret},
                  contextLine: secret,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
    expect(jsonEncode(transport.events), isNot(contains(secret)));
    expect(transport.events.single['release'], 'currency@test');
    expect(transport.events.single['environment'], 'test');
  });

  test('повторы ограничены, сбой доставки не ломает операцию', () async {
    for (var i = 0; i < 3; i++) {
      await reportError(
        StateError('storage'),
        StackTrace.current,
        'preferences.write',
        once: true,
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
    transport.fail = true;
    await reportError(StateError('storage'), StackTrace.current, 'theme.read');
    expect(await traceOperation('rates.load', () async => 42), 42);
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
  });
  testWidgets('ошибки настроек регистрируются без нарушения интерфейса', (
    tester,
  ) async {
    final api = ExchangeRatesApi(
      client: MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('currencies')
              ? '[{"iso_code":"USD","name":"Dollar"}]'
              : '[]',
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      CurrencyApp(
        api: api,
        preferencesStore: FailingPreferences(),
        themeStore: FailingTheme(),
        locationProvider: () async => null,
      ),
    );
    await tester.pumpAndSettle();
    for (final mode in ['dark', 'light']) {
      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('theme-$mode')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byKey(const Key('amount-field')), '987654');
    await tester.pumpAndSettle();
    final operations = transport.events
        .where((e) => e['exception'] != null)
        .map((e) => e['tags']['operation'])
        .toList();
    expect(
      operations,
      unorderedEquals([
        'theme.read',
        'preferences.read',
        'preferences.write',
        'theme.write',
      ]),
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(jsonEncode(transport.events), isNot(contains('987654')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'геолокация: ожидаемый таймаут не отправляется, исключение отправляется',
    (tester) async {
      for (final unexpected in [false, true]) {
        await tester.pumpWidget(
          CurrencyApp(
            key: UniqueKey(),
            api: ExchangeRatesApi(
              client: MockClient((_) async => http.Response('[]', 200)),
            ),
            locationProvider: () async {
              if (unexpected) throw StateError('private coordinates');
              throw TimeoutException('location');
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.system,
        );
        final errors = transport.events
            .where((e) => e['exception'] != null)
            .toList();
        expect(errors, hasLength(unexpected ? 1 : 0));
        if (unexpected) {
          expect(errors.single['tags']['operation'], 'theme.location');
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('повторяющаяся ошибка солнечного расчёта ограничена', () async {
    for (var i = 0; i < 3; i++) {
      expect(
        isSolarDay(DateTime.utc(7000), (latitude: 0.0, longitude: 0.0)),
        isNull,
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
    expect(transport.events.single['tags']['operation'], 'theme.calculate');
  });
  test('транзакции очищаются, автоматические операции исключаются', () async {
    await Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: 'SENSITIVE_987654'));
      scope.setContexts('location', {'latitude': 'SENSITIVE_987654'});
    });
    final automatic = Sentry.startTransaction('automatic', 'automatic');
    await automatic.finish();
    final manual = Sentry.startTransaction('rates.load', 'rates.load');
    manual.setData('amount', 'SENSITIVE_987654');
    final child = manual.startChild('private', description: 'SENSITIVE_987654');
    await child.finish();
    await manual.finish();
    await Future<void>.delayed(Duration.zero);
    expect(transport.events, hasLength(1));
    expect(transport.events.single['transaction'], 'rates.load');
    expect(jsonEncode(transport.events), isNot(contains('SENSITIVE_987654')));
  });
}
