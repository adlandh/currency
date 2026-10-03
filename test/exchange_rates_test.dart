import 'dart:async';
import 'dart:convert';

import 'package:currency/exchange_rates.dart';
import 'package:currency/rate_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('загружает и сортирует корректный каталог валют', () async {
    final api = ExchangeRatesApi(
      client: MockClient(
        (_) async => http.Response(
          '[{"iso_code":"USD","name":"US Dollar"},'
          '{"iso_code":"EUR","name":"Euro"},'
          '{"iso_code":"bad","name":"Ignored"},'
          '{"iso_code":"GBP","name":""}]',
          200,
        ),
      ),
    );

    final result = await api.fetchCurrencies();
    expect(result.map((item) => item.code), ['EUR', 'USD']);
  });

  test('загружает курсы и пропускает отсутствующие или неверные', () async {
    late Uri requestedUri;
    final api = ExchangeRatesApi(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '[{"date":"2026-09-04","base":"EUR","quote":"CZK","rate":25},'
          '{"date":"2026-09-04","base":"EUR","quote":"USD","rate":0},'
          '{"date":"2026-09-04","base":"EUR","quote":"GBP","rate":-1},'
          '{"date":"bad","base":"EUR","quote":"JPY","rate":150},'
          '{"date":"2026-09-04","base":"USD","quote":"CHF","rate":0.9}]',
          200,
        );
      }),
    );

    final result = await api.fetchRates('EUR', [
      'CZK',
      'USD',
      'GBP',
      'JPY',
      'CHF',
      'KWD',
    ]);
    expect(requestedUri.queryParameters['base'], 'EUR');
    expect(requestedUri.queryParameters['quotes'], 'CZK,USD,GBP,JPY,CHF,KWD');
    expect(result.keys, ['CZK']);
    expect(result['CZK']!.rate, 25);
    expect(result['CZK']!.date, DateTime.utc(2026, 9, 4));
  });

  test('не обращается к сети для совпадающей пары', () async {
    var calls = 0;
    final api = ExchangeRatesApi(
      client: MockClient((_) async {
        calls++;
        return http.Response('[]', 200);
      }),
    );
    expect(await api.fetchRates('EUR', ['EUR']), isEmpty);
    expect(calls, 0);
  });

  test('сообщает об HTTP-ошибке и неверном JSON', () async {
    final failed = ExchangeRatesApi(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      failed.fetchCurrencies(),
      throwsA(
        isA<ExchangeRatesException>()
            .having((e) => e.httpStatus, 'httpStatus', 503)
            .having((e) => e.transient, 'transient', isFalse),
      ),
    );

    final malformed = ExchangeRatesApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.fetchCurrencies(),
      throwsA(
        isA<ExchangeRatesException>().having(
          (e) => e.transient,
          'transient',
          isFalse,
        ),
      ),
    );
  });

  test('останавливает зависший запрос по таймауту', () async {
    final pending = Completer<http.Response>();
    final api = ExchangeRatesApi(
      client: MockClient((_) => pending.future),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      api.fetchCurrencies(),
      throwsA(
        isA<ExchangeRatesException>()
            .having((error) => error.message, 'message', contains('вовремя'))
            .having((error) => error.transient, 'transient', isTrue),
      ),
    );
  });
  test('сохраняет исходную сетевую причину и стек для диагностики', () async {
    final cause = http.ClientException('network');
    final stack = StackTrace.current;
    final api = ExchangeRatesApi(
      client: MockClient((_) async {
        Error.throwWithStackTrace(cause, stack);
      }),
    );
    await expectLater(
      api.fetchCurrencies(),
      throwsA(
        isA<ExchangeRatesException>()
            .having((e) => e.cause, 'cause', same(cause))
            .having((e) => e.causeStack.toString(), 'stack', stack.toString())
            .having(
              (e) => e.message,
              'message',
              'Не удалось связаться с источником курсов.',
            )
            .having((e) => e.transient, 'transient', isTrue),
      ),
    );
  });

  group('кэш курсов', () {
    late _MemoryCache cache;
    late DateTime now;
    late List<Uri> requests;
    var fail = false;

    ExchangeRatesApi api() => ExchangeRatesApi(
      cache: cache,
      now: () => now,
      client: MockClient((request) async {
        requests.add(request.url);
        if (fail) return http.Response('{}', 503);
        final quotes = request.url.queryParameters['quotes']!.split(',');
        return http.Response(
          jsonEncode([
            for (final quote in quotes)
              if (quote != 'KWD')
                {
                  'date': '2026-10-02',
                  'base': 'EUR',
                  'quote': quote,
                  'rate': quote == 'GBP' ? 0 : 2,
                },
          ]),
          200,
        );
      }),
    );

    List<String> quotesOf(Uri uri) => uri.queryParameters['quotes']!.split(',');

    setUp(() {
      cache = _MemoryCache();
      now = DateTime.utc(2026, 10, 3, 10);
      requests = [];
      fail = false;
    });

    test('полное попадание в течение 6 часов не обращается к сети', () async {
      await api().fetchRates('EUR', ['USD', 'CZK']);
      now = now.add(const Duration(hours: 5, minutes: 59));
      final result = await api().fetchRates('EUR', ['USD', 'CZK']);

      expect(requests, hasLength(1));
      expect(result.keys.toSet(), {'USD', 'CZK'});
      expect(result['USD']!.date, DateTime.utc(2026, 10, 2));
    });

    test('запись старше 6 часов запрашивается заново', () async {
      await api().fetchRates('EUR', ['USD']);
      now = now.add(const Duration(hours: 6, minutes: 1));
      await api().fetchRates('EUR', ['USD']);

      expect(requests, hasLength(2));
      expect(
        decodeRateCache(cache.value)['EUR:USD']!.fetchedAt,
        DateTime.utc(2026, 10, 3, 16, 1),
      );
    });

    test('частичное попадание запрашивает только недостающие пары', () async {
      await api().fetchRates('EUR', ['USD', 'CZK']);
      final result = await api().fetchRates('EUR', ['USD', 'CZK', 'JPY']);

      expect(quotesOf(requests.last), ['JPY']);
      expect(result.keys.toSet(), {'USD', 'CZK', 'JPY'});
      expect(decodeRateCache(cache.value).keys.toSet(), {
        'EUR:USD',
        'EUR:CZK',
        'EUR:JPY',
      });
    });

    test('force запрашивает все пары и обновляет время получения', () async {
      await api().fetchRates('EUR', ['USD', 'CZK']);
      now = now.add(const Duration(minutes: 10));
      await api().fetchRates('EUR', ['USD', 'CZK'], force: true);

      expect(requests, hasLength(2));
      expect(quotesOf(requests.last).toSet(), {'USD', 'CZK'});
      expect(
        decodeRateCache(cache.value)['EUR:USD']!.fetchedAt,
        DateTime.utc(2026, 10, 3, 10, 10),
      );
    });

    test('ошибка сети не меняет кэш', () async {
      await api().fetchRates('EUR', ['USD']);
      final before = cache.value;
      fail = true;

      await expectLater(
        api().fetchRates('EUR', ['USD'], force: true),
        throwsA(isA<ExchangeRatesException>()),
      );
      expect(cache.value, before);
    });

    test('отсутствующий или некорректный курс не кэшируется', () async {
      final result = await api().fetchRates('EUR', ['USD', 'KWD', 'GBP']);
      expect(result.keys, ['USD']);
      expect(decodeRateCache(cache.value).keys, ['EUR:USD']);

      await api().fetchRates('EUR', ['USD', 'KWD', 'GBP']);
      expect(quotesOf(requests.last).toSet(), {'KWD', 'GBP'});
    });

    test('запись из будущего считается несвежей', () async {
      await api().fetchRates('EUR', ['USD']);
      now = now.subtract(const Duration(minutes: 1));
      await api().fetchRates('EUR', ['USD']);

      expect(requests, hasLength(2));
    });

    test('повреждённый кэш игнорируется', () async {
      cache.value = '{bad';
      final result = await api().fetchRates('EUR', ['USD']);

      expect(requests, hasLength(1));
      expect(result.keys, ['USD']);
      expect(decodeRateCache(cache.value).keys, ['EUR:USD']);
    });

    test('просроченные записи удаляются при записи', () async {
      await api().fetchRates('EUR', ['USD']);
      now = now.add(const Duration(hours: 7));
      await api().fetchRates('EUR', ['CZK']);

      expect(decodeRateCache(cache.value).keys, ['EUR:CZK']);
    });

    test('поздний ответ раннего запроса не затирает обновлённый кэш', () async {
      final responses = <Completer<http.Response>>[];
      final racing = ExchangeRatesApi(
        cache: cache,
        now: () => now,
        client: MockClient((_) {
          responses.add(Completer<http.Response>());
          return responses.last.future;
        }),
      );
      http.Response body(Map<String, num> rates) => http.Response(
        jsonEncode([
          for (final MapEntry(:key, :value) in rates.entries)
            {'date': '2026-10-02', 'base': 'EUR', 'quote': key, 'rate': value},
        ]),
        200,
      );

      final early = racing.fetchRates('EUR', ['JPY']);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 1));
      final refresh = racing.fetchRates('EUR', ['USD', 'JPY'], force: true);
      await Future<void>.delayed(Duration.zero);

      responses[1].complete(body({'USD': 3, 'JPY': 170}));
      await refresh;
      responses[0].complete(body({'JPY': 160}));
      await early;

      final stored = decodeRateCache(cache.value);
      expect(stored['EUR:USD']!.rate.rate, 3);
      expect(stored['EUR:JPY']!.rate.rate, 170);
    });

    test('EUR не запрашивается и не кэшируется', () async {
      await api().fetchRates('EUR', ['EUR', 'USD']);

      expect(quotesOf(requests.single), ['USD']);
      expect(decodeRateCache(cache.value).keys, ['EUR:USD']);
    });
  });
}

class _MemoryCache implements RateCacheStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String value) => this.value = value;
}
