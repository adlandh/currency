import 'package:web/web.dart';

import 'rate_table_preferences.dart';

RateTablePreferencesStore createRateTablePreferencesStore() =>
    BrowserRateTablePreferencesStore();

class BrowserRateTablePreferencesStore implements RateTablePreferencesStore {
  BrowserRateTablePreferencesStore() : _storage = window.localStorage;

  final Storage _storage;

  @override
  RateTablePreferences? read() =>
      RateTablePreferences.decode(_storage.getItem(rateTablePreferencesKey));

  @override
  void write(RateTablePreferences preferences) =>
      _storage.setItem(rateTablePreferencesKey, preferences.encode());
}
