import 'package:currency/conversion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAmount', () {
    for (final entry in <String, double>{
      '3 000,50': 3000.5,
      '3000.50': 3000.5,
      '3\u00A0000,50': 3000.5,
      '3\u202F000.50': 3000.5,
      '  0  ': 0,
      '1000000000000': maximumAmount,
    }.entries) {
      test('принимает ${entry.key}', () {
        final result = parseAmount(entry.key);
        expect(result.status, AmountStatus.valid);
        expect(result.value, entry.value);
      });
    }

    for (final input in [
      '3,000.50',
      '30 00',
      '-1',
      '1e3',
      'NaN',
      '3000 EUR',
      '1000000000000.01',
    ]) {
      test('отклоняет $input', () {
        expect(parseAmount(input).status, AmountStatus.invalid);
      });
    }

    test('отличает пустой ввод', () {
      expect(parseAmount('   ').status, AmountStatus.empty);
    });
  });

  group('conversion', () {
    test('использует полный курс без промежуточного округления', () {
      expect(convertAmount(3000, 25), 75000);
      expect(convertAmount(3, 1.23456789), closeTo(3.70370367, 1e-10));
      expect(convertAmount(3000, 1), 3000);
    });

    test('отклоняет неконечный результат и неверный курс', () {
      expect(() => convertAmount(double.maxFinite, 2), throwsFormatException);
      expect(() => convertAmount(1, 0), throwsFormatException);
      expect(() => convertAmount(1, double.nan), throwsFormatException);
    });

    test('форматирует 0, 2 и 3 знака валюты', () {
      expect(_plain(formatMoney(12.3456, 'JPY')), '12 JPY');
      expect(_plain(formatMoney(12.3456, 'EUR')), '12,35 EUR');
      expect(_plain(formatMoney(12.3456, 'KWD')), '12,346 KWD');
      expect(_plain(formatMoney(75000, 'CZK')), '75 000,00 CZK');
    });
  });
}

String _plain(String value) => value.replaceAll(RegExp(r'[\u00A0\u202F]'), ' ');
