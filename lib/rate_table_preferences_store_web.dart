import 'package:web/web.dart';

import 'rate_table_preferences.dart';

RateTablePreferencesStore createRateTablePreferencesStore() =>
    BrowserRateTablePreferencesStore();

class BrowserRateTablePreferencesStore implements RateTablePreferencesStore {
  @override
  RateTablePreferences? read() => RateTablePreferences.decode(
    window.localStorage.getItem(rateTablePreferencesKey),
  );

  @override
  void write(RateTablePreferences preferences) => window.localStorage.setItem(
    rateTablePreferencesKey,
    preferences.encode(),
  );
}
