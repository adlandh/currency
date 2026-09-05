import 'dart:convert';

import 'package:currency/rate_table_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кодирует только базу и упорядоченный список целей', () {
    const preferences = RateTablePreferences(
      base: 'EUR',
      targets: ['CZK', 'USD'],
    );

    final encoded = jsonDecode(preferences.encode()) as Map<String, dynamic>;
    expect(encoded.keys, unorderedEquals(['base', 'targets']));
    expect(encoded, {
      'base': 'EUR',
      'targets': ['CZK', 'USD'],
    });
  });

  test('декодирует корректные настройки, включая пустой список', () {
    final preferences = RateTablePreferences.decode(
      '{"base":"CZK","targets":[]}',
    );

    expect(preferences?.base, 'CZK');
    expect(preferences?.targets, isEmpty);
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
