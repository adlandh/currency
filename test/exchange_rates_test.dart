import 'dart:async';

import 'package:currency/exchange_rates.dart';
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
      throwsA(isA<ExchangeRatesException>()),
    );

    final malformed = ExchangeRatesApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.fetchCurrencies(),
      throwsA(isA<ExchangeRatesException>()),
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
        isA<ExchangeRatesException>().having(
          (error) => error.message,
          'message',
          contains('вовремя'),
        ),
      ),
    );
  });
}
