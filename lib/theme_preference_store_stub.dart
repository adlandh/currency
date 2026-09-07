import 'theme_preference.dart';

ThemePreferenceStore createThemePreferenceStore() => const _MemoryThemeStore();

class _MemoryThemeStore implements ThemePreferenceStore {
  const _MemoryThemeStore();

  @override
  ThemePreference? read() => null;

  @override
  void write(ThemePreference mode) {}
}
