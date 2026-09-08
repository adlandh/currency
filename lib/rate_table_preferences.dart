import 'dart:convert';

import 'conversion.dart';

const rateTablePreferencesKey = 'currency.rate-table.v1';

class RateTablePreferences {
  const RateTablePreferences({
    required this.base,
    required this.targets,
    this.amount = '1',
  });

  final String base;
  final List<String> targets;
  final String amount;

  static final _currencyCode = RegExp(r'^[A-Z]{3}$');

  static RateTablePreferences? decode(String? source) {
    if (source == null) return null;

    try {
      final value = jsonDecode(source);
      if (value is! Map<String, dynamic>) return null;
      final base = value['base'];
      final targets = value['targets'];
      if (base is! String ||
          !_currencyCode.hasMatch(base) ||
          targets is! List ||
          targets.any(
            (target) => target is! String || !_currencyCode.hasMatch(target),
          )) {
        return null;
      }
      final savedAmount = value['amount'];
      final amount =
          savedAmount is String &&
              parseAmount(savedAmount).status == AmountStatus.valid
          ? savedAmount.trim()
          : '1';
      return RateTablePreferences(
        base: base,
        targets: targets.cast<String>().toList(),
        amount: amount,
      );
    } on FormatException {
      return null;
    }
  }

  String encode() =>
      jsonEncode({'base': base, 'targets': targets, 'amount': amount.trim()});
}

abstract interface class RateTablePreferencesStore {
  RateTablePreferences? read();

  void write(RateTablePreferences preferences);
}
