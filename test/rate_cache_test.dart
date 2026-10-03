import 'package:currency/exchange_rates.dart';
import 'package:currency/rate_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кодирует и разбирает записи кэша без потерь', () {
    final fetchedAt = DateTime.utc(2026, 10, 3, 10);
    final source = encodeRateCache({
      'EUR:USD': CachedRate(
        rate: ExchangeRate(
          base: 'EUR',
          quote: 'USD',
          rate: 1.17,
          date: DateTime.utc(2026, 10, 2),
        ),
        fetchedAt: fetchedAt,
      ),
    });

    final decoded = decodeRateCache(source);
    final entry = decoded['EUR:USD']!;
    expect(entry.rate.base, 'EUR');
    expect(entry.rate.quote, 'USD');
    expect(entry.rate.rate, 1.17);
    expect(entry.rate.date, DateTime.utc(2026, 10, 2));
    expect(entry.fetchedAt, fetchedAt);
  });

  test('повреждённый JSON и неверный корень дают пустой кэш', () {
    expect(decodeRateCache(null), isEmpty);
    expect(decodeRateCache('{bad'), isEmpty);
    expect(decodeRateCache('[1,2]'), isEmpty);
  });

  test('некорректные записи отбрасываются поштучно', () {
    const good =
        '"EUR:CZK":{"rate":25,"date":"2026-10-02",'
        '"fetchedAt":"2026-10-03T10:00:00.000Z"}';
    final decoded = decodeRateCache(
      '{$good,'
      '"EUR:USD":{"rate":"1.1","date":"2026-10-02","fetchedAt":"2026-10-03T10:00:00Z"},'
      '"EUR:GBP":{"rate":0,"date":"2026-10-02","fetchedAt":"2026-10-03T10:00:00Z"},'
      '"EUR:JPY":{"rate":160,"date":"bad","fetchedAt":"2026-10-03T10:00:00Z"},'
      '"EUR:KWD":{"rate":0.3,"date":"2026-10-02","fetchedAt":7},'
      '"eur:CHF":{"rate":1,"date":"2026-10-02","fetchedAt":"2026-10-03T10:00:00Z"},'
      '"EUR:SEK":5}',
    );
    expect(decoded.keys, ['EUR:CZK']);
    expect(decoded['EUR:CZK']!.rate.rate, 25);
  });
}
