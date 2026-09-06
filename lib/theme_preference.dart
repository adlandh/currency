import 'package:flutter/material.dart';

const themePreferenceKey = 'currency.theme.v1';

ThemeMode? decodeThemePreference(String? source) {
  switch (source) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return null;
  }
}

String encodeThemePreference(ThemeMode mode) =>
    mode == ThemeMode.dark ? 'dark' : 'light';

abstract interface class ThemePreferenceStore {
  ThemeMode? read();

  void write(ThemeMode mode);
}
