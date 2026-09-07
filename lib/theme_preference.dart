const themePreferenceKey = 'currency.theme.v1';

enum ThemePreference { auto, light, dark }

ThemePreference? decodeThemePreference(String? source) => switch (source) {
  'auto' => ThemePreference.auto,
  'light' => ThemePreference.light,
  'dark' => ThemePreference.dark,
  _ => null,
};

String encodeThemePreference(ThemePreference mode) => mode.name;

abstract interface class ThemePreferenceStore {
  ThemePreference? read();
  void write(ThemePreference mode);
}
