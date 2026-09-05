import 'rate_table_preferences.dart';
import 'rate_table_preferences_store_stub.dart'
    if (dart.library.js_interop) 'rate_table_preferences_store_web.dart'
    as platform;

RateTablePreferencesStore createRateTablePreferencesStore() =>
    platform.createRateTablePreferencesStore();
