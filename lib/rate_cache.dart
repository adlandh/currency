import 'dart:convert';

import 'exchange_rates.dart';

const rateCacheKey = 'currency.rate-cache.v1';

class CachedRate {
  const CachedRate({required this.rate, required this.fetchedAt});

  final ExchangeRate rate;
  final DateTime fetchedAt;
}

String rateCacheEntryKey(String base, String quote) => '$base:$quote';

final _entryKey = RegExp(r'^([A-Z]{3}):([A-Z]{3})$');

/// Некорректные записи отбрасываются поштучно, некорректный JSON даёт пустой кэш.
Map<String, CachedRate> decodeRateCache(String? source) {
  if (source == null) return {};
  final Object? value;
  try {
    value = jsonDecode(source);
  } on FormatException {
    return {};
  }
  if (value is! Map<String, dynamic>) return {};

  final entries = <String, CachedRate>{};
  for (final MapEntry(:key, value: item) in value.entries) {
    final match = _entryKey.firstMatch(key);
    if (match == null || item is! Map<String, dynamic>) continue;
    final rate = item['rate'];
    final date = item['date'];
    final fetchedAt = item['fetchedAt'];
    final parsedDate = date is String ? DateTime.tryParse(date) : null;
    final parsedFetchedAt = fetchedAt is String
        ? DateTime.tryParse(fetchedAt)
        : null;
    if (rate is! num ||
        !rate.isFinite ||
        rate <= 0 ||
        parsedDate == null ||
        parsedFetchedAt == null) {
      continue;
    }
    entries[key] = CachedRate(
      rate: ExchangeRate(
        base: match.group(1)!,
        quote: match.group(2)!,
        rate: rate.toDouble(),
        date: DateTime.utc(parsedDate.year, parsedDate.month, parsedDate.day),
      ),
      fetchedAt: parsedFetchedAt.toUtc(),
    );
  }
  return entries;
}

String encodeRateCache(Map<String, CachedRate> entries) => jsonEncode({
  for (final MapEntry(:key, :value) in entries.entries)
    key: {
      'rate': value.rate.rate,
      'date': value.rate.date.toIso8601String().substring(0, 10),
      'fetchedAt': value.fetchedAt.toUtc().toIso8601String(),
    },
});

abstract interface class RateCacheStore {
  String? read();

  void write(String value);
}
