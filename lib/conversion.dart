import 'package:intl/intl.dart';

const double maximumAmount = 1000000000000;

enum AmountStatus { empty, valid, invalid }

class AmountParseResult {
  const AmountParseResult._(this.status, this.value, this.error);

  const AmountParseResult.empty() : this._(AmountStatus.empty, null, null);

  const AmountParseResult.valid(double value)
    : this._(AmountStatus.valid, value, null);

  const AmountParseResult.invalid(String error)
    : this._(AmountStatus.invalid, null, error);

  final AmountStatus status;
  final double? value;
  final String? error;
}

final _amountPattern = RegExp(
  r'^(?:\d+|\d{1,3}(?:[ \u00A0\u202F]\d{3})+)(?:[.,]\d+)?$',
);

AmountParseResult parseAmount(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const AmountParseResult.empty();
  if (!_amountPattern.hasMatch(trimmed)) {
    return const AmountParseResult.invalid('Введите число, например 3 000,50.');
  }

  final normalized = trimmed
      .replaceAll(RegExp(r'[ \u00A0\u202F]'), '')
      .replaceAll(',', '.');
  final amount = double.tryParse(normalized);
  if (amount == null || !amount.isFinite || amount > maximumAmount) {
    return const AmountParseResult.invalid(
      'Максимальная сумма — 1 000 000 000 000.',
    );
  }
  return AmountParseResult.valid(amount);
}

double convertAmount(double amount, double rate, {bool reverse = false}) {
  if (!amount.isFinite || amount < 0 || !rate.isFinite || rate <= 0) {
    throw const FormatException('Невозможно рассчитать сумму.');
  }
  final result = reverse ? amount / rate : amount * rate;
  if (!result.isFinite) {
    throw const FormatException('Невозможно рассчитать сумму.');
  }
  return result;
}

int currencyFractionDigits(String currencyCode) =>
    NumberFormat.currency(locale: 'ru_RU', name: currencyCode).decimalDigits ??
    2;

String formatMoney(double amount, String currencyCode) {
  if (!amount.isFinite) throw const FormatException('Некорректная сумма.');
  final formatter = NumberFormat.decimalPatternDigits(
    locale: 'ru_RU',
    decimalDigits: currencyFractionDigits(currencyCode),
  );
  return '${formatter.format(amount)} $currencyCode';
}

String formatRate(double rate) {
  if (!rate.isFinite || rate <= 0) {
    throw const FormatException('Некорректный курс.');
  }
  final rounded = double.parse(rate.toStringAsPrecision(6));
  final magnitude = rounded.abs();
  final digits = magnitude >= 1000
      ? 2
      : magnitude >= 1
      ? 4
      : 6;
  final formatter = NumberFormat.decimalPatternDigits(
    locale: 'ru_RU',
    decimalDigits: digits,
  );
  final prefix = rounded == rate ? '' : '≈ ';
  return '$prefix${formatter.format(rounded)}';
}
