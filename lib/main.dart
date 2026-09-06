import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'currency_page.dart';
import 'exchange_rates.dart';
import 'rate_table_preferences.dart';
import 'rate_table_preferences_store.dart';
import 'theme_preference.dart';
import 'theme_preference_store.dart';

void main() {
  Intl.defaultLocale = 'ru_RU';
  runApp(CurrencyApp(api: ExchangeRatesApi()));
}

class CurrencyApp extends StatefulWidget {
  CurrencyApp({
    super.key,
    required this.api,
    RateTablePreferencesStore? preferencesStore,
    ThemePreferenceStore? themeStore,
  }) : preferencesStore = preferencesStore ?? createRateTablePreferencesStore(),
       themeStore = themeStore ?? createThemePreferenceStore();

  final ExchangeRatesApi api;
  final RateTablePreferencesStore preferencesStore;
  final ThemePreferenceStore themeStore;

  @override
  State<CurrencyApp> createState() => _CurrencyAppState();
}

const _appAccent = Color(0xFF285C4D);

class _CurrencyAppState extends State<CurrencyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    try {
      _themeMode = widget.themeStore.read() ?? ThemeMode.light;
    } catch (_) {
      _themeMode = ThemeMode.light;
    }
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    try {
      widget.themeStore.write(mode);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final lightColors =
        ColorScheme.fromSeed(
          seedColor: _appAccent,
          brightness: Brightness.light,
        ).copyWith(
          primary: _appAccent,
          onPrimary: const Color(0xFFF7FFFB),
          surface: const Color(0xFFFDFEFD),
          error: const Color(0xFF9E2F35),
        );
    final darkColors = ColorScheme.fromSeed(
      seedColor: _appAccent,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Курсы валют',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _buildTheme(lightColors, isLight: true),
      darkTheme: _buildTheme(darkColors, isLight: false),
      themeMode: _themeMode,
      home: CurrencyPage(
        api: widget.api,
        preferencesStore: widget.preferencesStore,
        themeMode: _themeMode,
        onThemeChanged: _setThemeMode,
      ),
    );
  }

  ThemeData _buildTheme(ColorScheme colors, {required bool isLight}) {
    final onText = isLight ? const Color(0xFF17221E) : colors.onSurface;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF5F8F6)
          : colors.surface,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 40,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
          color: onText,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: onText,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: onText,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          height: 1.5,
          color: isLight ? const Color(0xFF25352F) : colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: isLight ? const Color(0xFF42554E) : colors.onSurfaceVariant,
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
          borderSide: BorderSide(
            color: isLight ? const Color(0xFF73857E) : colors.outline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFF73857E) : colors.outline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isLight ? _appAccent : colors.primary,
            width: 2,
          ),
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
          foregroundColor: isLight ? const Color(0xFF1E4C3F) : colors.primary,
          side: BorderSide(
            color: isLight ? const Color(0xFF71867E) : colors.outline,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerTheme: DividerThemeData(
        color: isLight ? const Color(0xFFDDE5E1) : colors.outlineVariant,
      ),
    );
  }
}
