import 'theme_preference.dart';
import 'theme_preference_store_stub.dart'
    if (dart.library.js_interop) 'theme_preference_store_web.dart'
    as platform;

ThemePreferenceStore createThemePreferenceStore() =>
    platform.createThemePreferenceStore();
