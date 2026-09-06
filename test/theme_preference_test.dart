import 'package:currency/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кодирует и декодирует обе темы', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      expect(decodeThemePreference(encodeThemePreference(mode)), mode);
    }
  });

  test('отсутствующие и повреждённые значения отклоняются', () {
    for (final source in <String?>[
      null,
      '',
      'not-json',
      'system',
      'DARK',
      'dark ',
      'true',
    ]) {
      expect(
        decodeThemePreference(source),
        isNull,
        reason: 'Источник должен быть отклонён: $source',
      );
    }
  });
}
