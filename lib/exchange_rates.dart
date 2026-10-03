import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'observability.dart';
import 'rate_cache.dart';
import 'rate_cache_store.dart';

class CurrencyInfo {
  const CurrencyInfo({required this.code, required this.name});

  final String code;
  final String name;

  String get label => '$code · $name';

  @override
  bool operator ==(Object other) =>
      other is CurrencyInfo && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);
}

class ExchangeRate {
  const ExchangeRate({
    required this.base,
    required this.quote,
    required this.rate,
    required this.date,
  });

  final String base;
  final String quote;
  final double rate;
  final DateTime date;
}

class ExchangeRatesException extends ObservedException {
  const ExchangeRatesException(
    super.message, {
    super.cause,
    super.causeStack,
    super.httpStatus,
    super.transient,
  });
}

class ExchangeRatesApi {
  ExchangeRatesApi({
    http.Client? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 15),
    RateCacheStore? cache,
    DateTime Function()? now,
    this.cacheTtl = const Duration(hours: 6),
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://api.frankfurter.dev/v2/'),
       _cache = cache ?? createRateCacheStore(),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final Uri _baseUri;
  final Duration timeout;
  final RateCacheStore _cache;
  final DateTime Function() _now;
  final Duration cacheTtl;

  Future<List<CurrencyInfo>> fetchCurrencies() =>
      traceOperation('currencies.load', () async {
        final response = await _get(_baseUri.resolve('currencies'));
        final decoded = _decodeList(response.body, 'каталог валют');
        final currencies = <CurrencyInfo>[];

        for (final item in decoded) {
          final code = item['iso_code'];
          final name = item['name'];
          if (code is String &&
              RegExp(r'^[A-Z]{3}$').hasMatch(code) &&
              name is String &&
              name.trim().isNotEmpty) {
            currencies.add(CurrencyInfo(code: code, name: name.trim()));
          }
        }

        currencies.sort((a, b) => a.code.compareTo(b.code));
        return currencies;
      });

  /// Свежие курсы берутся из кэша; [force] запрашивает все пары у источника.
  Future<Map<String, ExchangeRate>> fetchRates(
    String base,
    Iterable<String> quotes, {
    bool force = false,
  }) async {
    final requested = quotes.where((quote) => quote != base).toSet();
    if (requested.isEmpty) return const {};

    final now = _now().toUtc();
    final fresh = {
      for (final MapEntry(:key, :value) in decodeRateCache(
        _cache.read(),
      ).entries)
        if (_isFresh(value, now)) key: value,
    };
    final cached = <String, ExchangeRate>{
      if (!force)
        for (final quote in requested)
          if (fresh[rateCacheEntryKey(base, quote)] case final hit?)
            quote: hit.rate,
    };
    final missing = requested.difference(cached.keys.toSet());
    if (missing.isEmpty) return cached;

    final fetched = await _fetchRates(base, missing);
    final fetchedAt = _now().toUtc();
    // Просроченные записи не попадают в fresh и удаляются при записи.
    _cache.write(
      encodeRateCache({
        ...fresh,
        for (final rate in fetched.values)
          rateCacheEntryKey(base, rate.quote): CachedRate(
            rate: rate,
            fetchedAt: fetchedAt,
          ),
      }),
    );
    return {...cached, ...fetched};
  }

  bool _isFresh(CachedRate entry, DateTime now) {
    final age = now.difference(entry.fetchedAt);
    return !age.isNegative && age < cacheTtl;
  }

  Future<Map<String, ExchangeRate>> _fetchRates(
    String base,
    Set<String> requested,
  ) {
    return traceOperation('rates.load', () async {
      final uri = _baseUri
          .resolve('rates')
          .replace(
            queryParameters: {'base': base, 'quotes': requested.join(',')},
          );
      final response = await _get(uri);
      final decoded = _decodeList(response.body, 'курсы валют');
      final rates = <String, ExchangeRate>{};

      for (final item in decoded) {
        final responseBase = item['base'];
        final quote = item['quote'];
        final value = item['rate'];
        final dateValue = item['date'];
        final date = dateValue is String ? DateTime.tryParse(dateValue) : null;
        final rate = value is num ? value.toDouble() : null;
        if (responseBase == base &&
            quote is String &&
            requested.contains(quote) &&
            rate != null &&
            rate.isFinite &&
            rate > 0 &&
            date != null) {
          rates[quote] = ExchangeRate(
            base: base,
            quote: quote,
            rate: rate,
            date: DateTime.utc(date.year, date.month, date.day),
          );
        }
      }

      return rates;
    });
  }

  Future<http.Response> _get(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException catch (error, stack) {
      throw ExchangeRatesException(
        'Источник курсов не ответил вовремя.',
        cause: error,
        causeStack: stack,
        transient: true,
      );
    } on Exception catch (error, stack) {
      throw ExchangeRatesException(
        'Не удалось связаться с источником курсов.',
        cause: error,
        causeStack: stack,
        transient: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExchangeRatesException(
        'Источник курсов вернул ошибку ${response.statusCode}.',
        httpStatus: response.statusCode,
      );
    }
    return response;
  }

  List<Map<String, Object?>> _decodeList(String body, String resource) {
    try {
      final value = jsonDecode(body);
      if (value is! List) throw const FormatException();
      return value.map((item) {
        if (item is! Map<String, dynamic>) throw const FormatException();
        return item.cast<String, Object?>();
      }).toList();
    } on FormatException catch (error, stack) {
      throw ExchangeRatesException(
        'Получен некорректный ответ: $resource.',
        cause: error,
        causeStack: stack,
      );
    }
  }
}
