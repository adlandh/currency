import 'dart:convert';

import 'package:currency/rate_table_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кодирует базу, цели и сумму с сохранением локального формата', () {
    const preferences = RateTablePreferences(
      base: 'EUR',
      targets: ['CZK', 'USD'],
      amount: ' 3 000,50 ',
    );

    final encoded = jsonDecode(preferences.encode()) as Map<String, dynamic>;
    expect(encoded, {
      'base': 'EUR',
      'targets': ['CZK', 'USD'],
      'amount': '3 000,50',
    });
  });

  test('декодирует старые настройки с суммой по умолчанию', () {
    final preferences = RateTablePreferences.decode(
      '{"base":"CZK","targets":[]}',
    );

    expect(preferences?.base, 'CZK');
    expect(preferences?.targets, isEmpty);
    expect(preferences?.amount, '1');
  });

  test('декодирует локализованную сумму без крайних пробелов', () {
    final preferences = RateTablePreferences.decode(
      '{"base":"EUR","targets":["CZK"],"amount":" 12,3456 "}',
    );

    expect(preferences?.amount, '12,3456');
  });

  test('заменяет только повреждённую сумму на значение по умолчанию', () {
    for (final amount in [null, 42, '', '-1', '3,000.50', '1000000000001']) {
      final preferences = RateTablePreferences.decode(
        jsonEncode({
          'base': 'EUR',
          'targets': ['CZK'],
          'amount': amount,
        }),
      );

      expect(preferences?.base, 'EUR');
      expect(preferences?.targets, ['CZK']);
      expect(preferences?.amount, '1');
    }
  });

  test('игнорирует отсутствующие и повреждённые настройки', () {
    for (final source in <String?>[
      null,
      '',
      'not-json',
      '[]',
      '{}',
      '{"base":42,"targets":[]}',
      '{"base":"eur","targets":[]}',
      '{"base":"EURO","targets":[]}',
      '{"base":"EUR","targets":"CZK"}',
      '{"base":"EUR","targets":["CZK",42]}',
      '{"base":"EUR","targets":["czk"]}',
    ]) {
      expect(
        RateTablePreferences.decode(source),
        isNull,
        reason: 'Источник должен быть отклонён: $source',
      );
    }
  });
}
