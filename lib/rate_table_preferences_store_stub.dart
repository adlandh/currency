import 'rate_table_preferences.dart';

RateTablePreferencesStore createRateTablePreferencesStore() =>
    const _MemoryPreferencesStore();

class _MemoryPreferencesStore implements RateTablePreferencesStore {
  const _MemoryPreferencesStore();

  @override
  RateTablePreferences? read() => null;

  @override
  void write(RateTablePreferences preferences) {}
}
