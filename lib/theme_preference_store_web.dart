import 'package:flutter/material.dart';
import 'package:web/web.dart';

import 'theme_preference.dart';

ThemePreferenceStore createThemePreferenceStore() =>
    BrowserThemePreferenceStore();

class BrowserThemePreferenceStore implements ThemePreferenceStore {
  BrowserThemePreferenceStore() : _storage = window.localStorage;

  final Storage _storage;

  @override
  ThemeMode? read() => decodeThemePreference(_storage.getItem(themePreferenceKey));

  @override
  void write(ThemeMode mode) =>
      _storage.setItem(themePreferenceKey, encodeThemePreference(mode));
}
