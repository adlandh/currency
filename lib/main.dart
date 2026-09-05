import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'currency_page.dart';
import 'exchange_rates.dart';
import 'rate_table_preferences.dart';
import 'rate_table_preferences_store.dart';

void main() {
  Intl.defaultLocale = 'ru_RU';
  runApp(CurrencyApp(api: ExchangeRatesApi()));
}

class CurrencyApp extends StatelessWidget {
  CurrencyApp({
    super.key,
    required this.api,
    RateTablePreferencesStore? preferencesStore,
  }) : preferencesStore = preferencesStore ?? createRateTablePreferencesStore();

  final ExchangeRatesApi api;
  final RateTablePreferencesStore preferencesStore;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF285C4D);
    final colors =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          onPrimary: const Color(0xFFF7FFFB),
          surface: const Color(0xFFFDFEFD),
          error: const Color(0xFF9E2F35),
        );

    return MaterialApp(
      title: 'Курсы валют',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF5F8F6),
        textTheme: const TextTheme(
          displaySmall: TextStyle(
            fontSize: 40,
            height: 1.08,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: Color(0xFF17221E),
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: Color(0xFF17221E),
          ),
          titleMedium: TextStyle(
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: Color(0xFF17221E),
          ),
          bodyLarge: TextStyle(
            fontSize: 17,
            height: 1.5,
            color: Color(0xFF25352F),
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Color(0xFF42554E),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF73857E)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF73857E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: accent, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.error, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: const Color(0xFF1E4C3F),
            side: const BorderSide(color: Color(0xFF71867E)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFDDE5E1)),
      ),
      home: CurrencyPage(api: api, preferencesStore: preferencesStore),
    );
  }
}
