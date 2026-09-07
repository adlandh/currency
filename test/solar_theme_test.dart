import 'package:currency/solar_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('эталонные восход и закат с допуском одной минуты', () {
    // NREL/TP-560-34302, таблица A2.1: 02.01.1994, 35° N, 0° E.
    // https://docs.nrel.gov/docs/fy08osti/34302.pdf
    // SPA: восход 07:08:12.8 UTC, закат 16:59:55.9 UTC.
    const location = (latitude: 35.0, longitude: 0.0);
    for (final (event, after) in [
      (DateTime.utc(1994, 1, 2, 7, 8, 13), true),
      (DateTime.utc(1994, 1, 2, 16, 59, 56), false),
    ]) {
      expect(
        isSolarDay(event.subtract(const Duration(minutes: 1)), location),
        !after,
      );
      expect(
        isSolarDay(event.add(const Duration(minutes: 1)), location),
        after,
      );
    }
  });

  test('полярный день, ночь и переход UTC суток', () {
    for (final (instant, latitude, longitude, day) in [
      (DateTime.utc(2026, 6, 21), 78.0, 15.0, true),
      (DateTime.utc(2026, 12, 21, 12), 78.0, 15.0, false),
      (DateTime.utc(2026, 3, 20, 23, 59), 0.0, 180.0, true),
      (DateTime.utc(2026, 3, 21), 0.0, 180.0, true),
      (DateTime.utc(2026, 3, 21), 0.0, 0.0, false),
    ]) {
      expect(
        isSolarDay(instant, (latitude: latitude, longitude: longitude)),
        day,
      );
    }
  });

  test('абсолютный момент не зависит от часового пояса', () {
    const location = (latitude: 35.0, longitude: 0.0);
    final utc = DateTime.parse('1994-01-02T07:10:00Z');
    for (final instant in [
      utc.toLocal(),
      DateTime.parse('1994-01-02T16:10:00+09:00'),
    ]) {
      expect(isSolarDay(instant, location), isSolarDay(utc, location));
    }
  });

  test('неверные координаты и ошибка расчёта не дают палитру', () {
    for (final location in [
      (latitude: double.nan, longitude: 0.0),
      (latitude: 0.0, longitude: double.infinity),
      (latitude: 91.0, longitude: 0.0),
      (latitude: 0.0, longitude: -181.0),
    ]) {
      expect(isSolarDay(DateTime.utc(2026), location), isNull);
    }
    expect(
      isSolarDay(DateTime.utc(7000), (latitude: 0.0, longitude: 0.0)),
      isNull,
    );
  });
}
