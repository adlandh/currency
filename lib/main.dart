import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'currency_page.dart';
import 'exchange_rates.dart';
import 'observability.dart';
import 'rate_table_preferences.dart';
import 'rate_table_preferences_store.dart';
import 'solar_theme.dart';
import 'theme_location.dart';
import 'theme_preference.dart';
import 'theme_preference_store.dart';

Future<void> main() => runWithObservability(() {
  Intl.defaultLocale = 'ru_RU';
  runApp(CurrencyApp(api: ExchangeRatesApi()));
});

class CurrencyApp extends StatefulWidget {
  CurrencyApp({
    super.key,
    required this.api,
    RateTablePreferencesStore? preferencesStore,
    ThemePreferenceStore? themeStore,
    DateTime Function()? clock,
    Future<ThemeLocation?> Function()? locationProvider,
  }) : preferencesStore = preferencesStore ?? createRateTablePreferencesStore(),
       themeStore = themeStore ?? createThemePreferenceStore(),
       clock = clock ?? DateTime.now,
       locationProvider = locationProvider ?? getThemeLocation;

  final ExchangeRatesApi api;
  final RateTablePreferencesStore preferencesStore;
  final ThemePreferenceStore themeStore;
  final DateTime Function() clock;
  final Future<ThemeLocation?> Function() locationProvider;

  @override
  State<CurrencyApp> createState() => _CurrencyAppState();
}

const _appAccent = Color(0xFF285C4D);

class _CurrencyAppState extends State<CurrencyApp> with WidgetsBindingObserver {
  ThemePreference _preference = ThemePreference.auto;
  ThemeMode _themeMode = ThemeMode.system;
  ThemeLocation? _location;
  String? _locationStatus;
  Timer? _timer;
  int _generation = 0;
  bool _requestPending = false;
  bool _locationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _preference = widget.themeStore.read() ?? ThemePreference.auto;
    } catch (error, stack) {
      unawaited(reportError(error, stack, 'theme.read', once: true));
    }
    _applyPreference();
  }

  void _setThemePreference(ThemePreference preference) {
    setState(() {
      _preference = preference;
      _applyPreference();
    });
    try {
      widget.themeStore.write(preference);
    } catch (error, stack) {
      unawaited(reportError(error, stack, 'theme.write', once: true));
    }
  }

  void _applyPreference() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _locationFailed = false;
    if (_preference == ThemePreference.auto) {
      _recalculate();
      // ponytail: до минуты задержки; точный таймер нужен для секундной границы.
      _timer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _recalculate(),
      );
      unawaited(_refreshLocation());
    } else {
      _themeMode = _preference == ThemePreference.dark
          ? ThemeMode.dark
          : ThemeMode.light;
      _locationStatus = null;
    }
  }

  void _recalculate() {
    if (_preference != ThemePreference.auto) return;
    final day = _location == null
        ? null
        : isSolarDay(widget.clock(), _location!);
    final mode = day == null
        ? ThemeMode.system
        : (day ? ThemeMode.light : ThemeMode.dark);
    final status = _location != null && day == null
        ? 'Не удалось определить день и ночь — используется системная тема'
        : (_requestPending || _location == null ? _locationStatus : null);
    if (mode != _themeMode || status != _locationStatus) {
      setState(() {
        _themeMode = mode;
        _locationStatus = status;
      });
    }
  }

  Future<void> _refreshLocation() async {
    if (_requestPending ||
        _locationFailed ||
        _preference != ThemePreference.auto) {
      return;
    }
    final generation = _generation;
    _requestPending = true;
    setState(() => _locationStatus = 'Определяем местоположение');
    ThemeLocation? location;
    try {
      location = await widget.locationProvider().timeout(
        const Duration(seconds: 10),
      );
      if (location != null && !validThemeLocation(location)) location = null;
    } on TimeoutException {
      // Недоступная геолокация — штатное резервное поведение.
    } catch (error, stack) {
      unawaited(reportError(error, stack, 'theme.location'));
    }
    _requestPending = false;
    if (!mounted) return;
    if (generation != _generation) {
      if (_preference == ThemePreference.auto) unawaited(_refreshLocation());
      return;
    }
    setState(() {
      _location = location;
      _locationFailed = location == null;
      _locationStatus = location == null
          ? 'Местоположение недоступно — используется системная тема'
          : null;
    });
    _recalculate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _preference == ThemePreference.auto) {
      _recalculate();
      unawaited(_refreshLocation());
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        themePreference: _preference,
        themeStatus: _locationStatus,
        onThemeChanged: _setThemePreference,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: isLight ? const Color(0xFF1E4C3F) : colors.primary,
          side: BorderSide(
            color: isLight ? const Color(0xFF71867E) : colors.outline,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
