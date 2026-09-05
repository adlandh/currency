import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

class ExchangeRatesException implements Exception {
  const ExchangeRatesException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExchangeRatesApi {
  ExchangeRatesApi({
    http.Client? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://api.frankfurter.dev/v2/');

  final http.Client _client;
  final Uri _baseUri;
  final Duration timeout;

  Future<List<CurrencyInfo>> fetchCurrencies() async {
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
  }

  Future<Map<String, ExchangeRate>> fetchRates(
    String base,
    Iterable<String> quotes,
  ) async {
    final requested = quotes.where((quote) => quote != base).toSet();
    if (requested.isEmpty) return const {};

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
  }

  Future<http.Response> _get(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const ExchangeRatesException('Источник курсов не ответил вовремя.');
    } on Exception {
      throw const ExchangeRatesException(
        'Не удалось связаться с источником курсов.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExchangeRatesException(
        'Источник курсов вернул ошибку ${response.statusCode}.',
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
    } on FormatException {
      throw ExchangeRatesException('Получен некорректный ответ: $resource.');
    }
  }
}
