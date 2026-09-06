import 'package:flutter/material.dart';

import 'theme_preference.dart';

ThemePreferenceStore createThemePreferenceStore() => const _MemoryThemeStore();

class _MemoryThemeStore implements ThemePreferenceStore {
  const _MemoryThemeStore();

  @override
  ThemeMode? read() => null;

  @override
  void write(ThemeMode mode) {}
}
