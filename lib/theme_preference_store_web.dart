import 'package:web/web.dart';

import 'theme_preference.dart';

ThemePreferenceStore createThemePreferenceStore() =>
    BrowserThemePreferenceStore();

class BrowserThemePreferenceStore implements ThemePreferenceStore {
  @override
  ThemePreference? read() =>
      decodeThemePreference(window.localStorage.getItem(themePreferenceKey));

  @override
  void write(ThemePreference mode) => window.localStorage.setItem(
    themePreferenceKey,
    encodeThemePreference(mode),
  );
}
