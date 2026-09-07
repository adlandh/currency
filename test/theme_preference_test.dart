import 'package:currency/theme_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кодирует и декодирует три режима', () {
    for (final mode in ThemePreference.values) {
      expect(decodeThemePreference(encodeThemePreference(mode)), mode);
    }
  });

  test('совместим с прежним хранилищем', () {
    expect(themePreferenceKey, 'currency.theme.v1');
    expect(decodeThemePreference('light'), ThemePreference.light);
    expect(decodeThemePreference('dark'), ThemePreference.dark);
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
