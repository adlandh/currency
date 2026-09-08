import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'conversion.dart';
import 'exchange_rates.dart';
import 'rate_table_preferences.dart';
import 'theme_preference.dart';

class CurrencyPage extends StatefulWidget {
  const CurrencyPage({
    super.key,
    required this.api,
    required this.preferencesStore,
    required this.themePreference,
    this.themeStatus,
    required this.onThemeChanged,
  });

  final ExchangeRatesApi api;
  final RateTablePreferencesStore preferencesStore;
  final ThemePreference themePreference;
  final String? themeStatus;
  final ValueChanged<ThemePreference> onThemeChanged;

  @override
  State<CurrencyPage> createState() => _CurrencyPageState();
}

class _CurrencyPageState extends State<CurrencyPage> {
  final _themeFocus = FocusNode();
  final _amountController = TextEditingController(text: '1');

  List<CurrencyInfo> _currencies = const [];
  List<String> _targets = const [];
  static const _base = 'EUR';

  bool _catalogLoading = true;
  String? _catalogError;
  Map<String, ExchangeRate> _tableRates = const {};
  Set<String> _missingTableRates = const {};
  bool _tableLoading = false;
  String? _tableError;
  bool _tableRefreshWarning = false;
  RateTablePreferences? _savedPreferences;
  String? _preferencesNotice;

  int _catalogRequest = 0;
  int _tableRequest = 0;
  int _addMenuVersion = 0;

  @override
  void initState() {
    super.initState();
    try {
      _savedPreferences = widget.preferencesStore.read();
      _amountController.text = _savedPreferences?.amount ?? '1';
    } catch (_) {
      _preferencesNotice = 'Не удалось восстановить настройки. Используются значения по умолчанию.';
    }
    unawaited(_loadCurrencies());
  }

  @override
  void dispose() {
    _catalogRequest++;
    _tableRequest++;
    _themeFocus.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    final request = ++_catalogRequest;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });

    try {
      final currencies = await widget.api.fetchCurrencies();
      if (!mounted || request != _catalogRequest) return;
      final codes = currencies.map((currency) => currency.code).toSet();
      final saved = _savedPreferences;
      final targets = saved == null
          ? ['USD', 'CZK', 'GBP'].where(codes.contains).toList()
          : _availableUnique(saved.targets, codes);
      setState(() {
        _currencies = currencies;
        _catalogLoading = false;
        _targets = targets;
        _tableRates = const {};
        _missingTableRates = const {};
      });
      if (currencies.isNotEmpty) {
        _persistRateTablePreferences(clearNoticeOnSuccess: false);
        unawaited(_loadTableRates());
      }
    } on ExchangeRatesException catch (error) {
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = error.message;
        _currencies = const [];
      });
    }
  }

  List<String> _availableUnique(List<String> targets, Set<String> codes) {
    final seen = <String>{};
    return [
      for (final target in targets)
        if (codes.contains(target) && seen.add(target)) target,
    ];
  }

  Future<void> _loadTableRates({bool refresh = false}) async {
    final base = _base;
    final targets = List<String>.of(_targets);
    final request = ++_tableRequest;
    final requested = targets.where((target) => target != base).toSet();
    if (requested.isEmpty) {
      setState(() {
        _tableRates = const {};
        _missingTableRates = const {};
        _tableLoading = false;
        _tableError = null;
        _tableRefreshWarning = false;
      });
      return;
    }

    setState(() {
      _tableLoading = true;
      _tableError = null;
      _tableRefreshWarning = false;
      if (!refresh) {
        _tableRates = const {};
        _missingTableRates = const {};
      }
    });

    try {
      final rates = await widget.api.fetchRates(base, requested);
      if (!_tableRequestIsCurrent(request, targets)) return;
      setState(() {
        _tableLoading = false;
        _tableRates = rates;
        _missingTableRates = requested.difference(rates.keys.toSet());
      });
    } on ExchangeRatesException catch (error) {
      if (!_tableRequestIsCurrent(request, targets)) return;
      setState(() {
        _tableLoading = false;
        if (refresh && _tableRates.isNotEmpty) {
          _tableRefreshWarning = true;
        } else {
          _tableRates = const {};
          _missingTableRates = requested;
          _tableError = error.message;
        }
      });
    }
  }

  bool _tableRequestIsCurrent(int request, List<String> targets) {
    return mounted && request == _tableRequest && _sameItems(targets, _targets);
  }

  bool _sameItems(List<String> left, List<String> right) =>
      left.length == right.length &&
      Iterable.generate(left.length)
          .every((index) => left[index] == right[index]);

  Future<void> _refreshAll() async {
    if (_catalogError != null || _currencies.isEmpty) {
      await _loadCurrencies();
      return;
    }
    await _loadTableRates(refresh: true);
  }

  void _addTarget(String? value) {
    if (value == null || _targets.contains(value)) return;
    setState(() {
      _targets = [..._targets, value];
      _addMenuVersion++;
    });
    _persistRateTablePreferences();
    unawaited(_loadTableRates());
  }

  void _removeTarget(String value) {
    setState(() => _targets = _targets.where((code) => code != value).toList());
    _persistRateTablePreferences();
    unawaited(_loadTableRates());
  }

  void _persistRateTablePreferences({bool clearNoticeOnSuccess = true}) {
    final base = _base;
    final enteredAmount = _amountController.text;
    final amount = parseAmount(enteredAmount).status == AmountStatus.valid
        ? enteredAmount.trim()
        : _savedPreferences?.amount ?? '1';
    final preferences = RateTablePreferences(
      base: base,
      targets: List<String>.of(_targets),
      amount: amount,
    );
    _savedPreferences = preferences;
    try {
      widget.preferencesStore.write(preferences);
      if (clearNoticeOnSuccess && _preferencesNotice != null) {
        setState(() => _preferencesNotice = null);
      }
    } catch (_) {
      const message =
          'Не удалось сохранить настройки. Текущий выбор останется только до закрытия страницы.';
      if (_preferencesNotice != message) {
        setState(() => _preferencesNotice = message);
      }
    }
  }

  CurrencyInfo? _currency(String? code) {
    if (code == null) return null;
    for (final currency in _currencies) {
      if (currency.code == code) return currency;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 600
        ? 20.0
        : 48.0;
    return Scaffold(
      body: SafeArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            primary: true,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              40,
              horizontalPadding,
              48,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    if (_preferencesNotice != null) ...[
                      const SizedBox(height: 24),
                      Semantics(
                        key: const Key('preferences-notice'),
                        liveRegion: true,
                        child: _InlineNotice(
                          icon: Icons.warning_amber_rounded,
                          text: _preferencesNotice!,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ] else
                      const SizedBox(height: 40),
                    if (_catalogLoading)
                      const _CatalogLoading()
                    else if (_catalogError != null)
                      _CatalogFailure(
                        message: _catalogError!,
                        onRetry: _loadCurrencies,
                      )
                    else if (_currencies.isEmpty)
                      _CatalogFailure(
                        message: 'Источник не вернул доступные валюты.',
                        onRetry: _loadCurrencies,
                      )
                    else
                      _buildRates(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = switch (widget.themePreference) {
      ThemePreference.auto => 'Авто, ${isDark ? 'тёмная' : 'светлая'}',
      ThemePreference.light => 'Светлая',
      ThemePreference.dark => 'Тёмная',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Курсы валют', style: Theme.of(context).textTheme.displaySmall),
        IconButton(
          key: const Key('refresh-button'),
          onPressed: _refreshAll,
          tooltip: 'Обновить',
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
        MenuAnchor(
          childFocusNode: _themeFocus,
          onClose: () => _themeFocus.requestFocus(),
          menuChildren: [
            for (final (preference, title) in const [
              (ThemePreference.auto, 'Авто'),
              (ThemePreference.light, 'Светлая'),
              (ThemePreference.dark, 'Тёмная'),
            ])
              MenuItemButton(
                key: Key('theme-${preference.name}'),
                autofocus: preference == ThemePreference.auto,
                onPressed: () => widget.onThemeChanged(preference),
                leadingIcon: SizedBox(
                  width: 24,
                  child: widget.themePreference == preference
                      ? const Icon(Icons.check, size: 20)
                      : null,
                ),
                child: Semantics(
                  selected: widget.themePreference == preference,
                  child: Text(title),
                ),
              ),
            if (widget.themePreference == ThemePreference.auto &&
                widget.themeStatus != null)
              SizedBox(
                width: 260,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.themeStatus!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
          ],
          builder: (context, controller, child) => IconButton(
            key: const Key('theme-toggle-button'),
            focusNode: _themeFocus,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            tooltip: 'Тема: $label',
            icon: Icon(switch (widget.themePreference) {
              ThemePreference.auto => Icons.brightness_auto_rounded,
              ThemePreference.light => Icons.light_mode_rounded,
              ThemePreference.dark => Icons.dark_mode_rounded,
            }, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildRates(BuildContext context) {
    final amount = parseAmount(_amountController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('amount-field'),
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            fontSize: 17,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            labelText: 'Сумма',
            hintText: 'Например, 3 000,50',
            helperText: amount.status == AmountStatus.empty
                ? 'Введите сумму'
                : null,
            errorText: amount.status == AmountStatus.invalid
                ? amount.error
                : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            setState(() {});
            if (parseAmount(_amountController.text).status ==
                AmountStatus.valid) {
              _persistRateTablePreferences();
            }
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Одна сумма для обоих направлений: из EUR в валюту строки и обратно',
        ),
        const SizedBox(height: 24),
        if (_tableError != null) ...[
          _FailureBanner(message: _tableError!, onRetry: _loadTableRates),
          const SizedBox(height: 16),
        ],
        if (_targets.isEmpty)
          const _EmptyRates()
        else
          Semantics(
            key: const Key('conversion-semantics'),
            liveRegion: true,
            container: true,
            explicitChildNodes: true,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 900 ||
                      MediaQuery.textScalerOf(context).scale(17) > 25;
                  return Column(
                    children: [
                      if (!compact) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 12, 16),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text('Валюта')),
                              SizedBox(width: 20),
                              Expanded(flex: 4, child: Text('Курс')),
                              SizedBox(width: 20),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'EUR → валюта',
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              SizedBox(width: 20),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'Валюта → EUR',
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              SizedBox(width: 56),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      for (var index = 0; index < _targets.length; index++) ...[
                        RateRow(
                          key: Key('rate-row-${_targets[index]}'),
                          currency: _currency(_targets[index])!,
                          base: _base,
                          rate: _tableRates[_targets[index]],
                          identity: _targets[index] == _base,
                          missing: _missingTableRates.contains(_targets[index]),
                          loading: _tableLoading,
                          amount: amount,
                          compact: compact,
                          onRemove: () => _removeTarget(_targets[index]),
                        ),
                        if (index != _targets.length - 1)
                          const Divider(height: 1, indent: 20, endIndent: 20),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        if (_tableRefreshWarning) ...[
          const SizedBox(height: 12),
          const _InlineNotice(
            icon: Icons.info_outline_rounded,
            text: 'Не удалось обновить. Показаны предыдущие курсы.',
          ),
        ],
        const SizedBox(height: 24),
        CurrencyMenu(
          key: ValueKey('add-$_addMenuVersion-${_currencies.length}'),
          fieldKey: const Key('add-target-menu'),
          label: 'Добавить валюту',
          currencies: _currencies,
          disabledCodes: _targets.toSet(),
          onSelected: _addTarget,
        ),
        if (_targets.length == _currencies.length) ...[
          const SizedBox(height: 8),
          const Text('Все валюты уже добавлены.'),
        ],
        const SizedBox(height: 18),
        Text(
          'Источник: Frankfurter. Ежедневные справочные курсы; банковские комиссии не учитываются.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class CurrencyMenu extends StatelessWidget {
  const CurrencyMenu({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.currencies,
    required this.onSelected,
    this.disabledCodes = const {},
  });

  final Key fieldKey;
  final String label;
  final List<CurrencyInfo> currencies;
  final Set<String> disabledCodes;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: LayoutBuilder(
        builder: (context, constraints) => DropdownMenu<String>(
          key: fieldKey,
          width: constraints.maxWidth,
          label: Text(label),
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          menuHeight: 360,
          leadingIcon: const Icon(Icons.search_rounded, size: 20),
          inputDecorationTheme: Theme.of(context).inputDecorationTheme,
          dropdownMenuEntries: currencies
              .map(
                (currency) => DropdownMenuEntry(
                  value: currency.code,
                  label: currency.label,
                  enabled: !disabledCodes.contains(currency.code),
                ),
              )
              .toList(),
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class RateRow extends StatefulWidget {
  const RateRow({
    super.key,
    required this.currency,
    required this.base,
    required this.rate,
    required this.identity,
    required this.missing,
    required this.loading,
    required this.amount,
    required this.compact,
    required this.onRemove,
  });

  final CurrencyInfo currency;
  final String base;
  final ExchangeRate? rate;
  final bool identity;
  final bool missing;
  final bool loading;
  final AmountParseResult amount;
  final bool compact;
  final VoidCallback onRemove;

  @override
  State<RateRow> createState() => _RateRowState();
}

class _RateRowState extends State<RateRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: _hovered
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          boxShadow: _hovered
              ? const [
                  BoxShadow(
                    color: Color(0x0D244C40),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Color(0x0A244C40),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : const [],
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = _details(context);
            final name = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.currency.code,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.currency.name,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            );
            final remove = IconButton(
              key: Key('remove-${widget.currency.code}'),
              onPressed: widget.onRemove,
              tooltip: 'Удалить ${widget.currency.code}',
              icon: const Icon(Icons.close_rounded, size: 20),
            );
            if (widget.compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      remove,
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Курс'),
                  details,
                  const SizedBox(height: 14),
                  Text('${widget.base} → ${widget.currency.code}'),
                  _result(context),
                  const SizedBox(height: 14),
                  Text('${widget.currency.code} → ${widget.base}'),
                  _result(context, reverse: true),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: name),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: details),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _result(context)),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _result(context, reverse: true)),
                const SizedBox(width: 8),
                remove,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _result(BuildContext context, {bool reverse = false}) {
    final from = reverse ? widget.currency.code : widget.base;
    final to = reverse ? widget.base : widget.currency.code;
    final rate = widget.identity ? 1.0 : widget.rate?.rate;
    String result;
    if (widget.amount.status == AmountStatus.empty) {
      result = 'Введите сумму';
    } else if (widget.amount.status == AmountStatus.invalid) {
      result = 'Исправьте сумму';
    } else if (rate == null) {
      result = widget.loading && !widget.missing
          ? 'Загрузка курса…'
          : 'Курс недоступен';
    } else {
      try {
        result = formatMoney(
          convertAmount(widget.amount.value!, rate, reverse: reverse),
          to,
        );
      } on FormatException {
        result = 'Не удалось рассчитать сумму.';
      }
    }
    return Text(
      result.replaceAll('\u00a0', ' '),
      key: Key(
        '${reverse ? 'reverse' : 'conversion'}-result-${widget.currency.code}',
      ),
      semanticsLabel: 'Результат конвертации $from → $to: $result',
      textAlign: widget.compact ? TextAlign.left : TextAlign.right,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }

  Widget _details(BuildContext context) {
    final rate = widget.identity ? 1.0 : widget.rate?.rate;
    final value = rate != null
        ? '1 ${widget.base} = ${formatRate(rate)} ${widget.currency.code}'
        : widget.loading && !widget.missing
        ? 'Загрузка курса…'
        : 'Курс недоступен';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (!widget.identity && widget.rate != null) ...[
          const SizedBox(height: 4),
          Text(
            'За ${DateFormat.yMMMMd('ru_RU').format(widget.rate!.date)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (widget.identity) ...[
          const SizedBox(height: 4),
          Text(
            'Тождественный курс',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Загружаем список валют…'),
          ],
        ),
      ),
    );
  }
}

class _CatalogFailure extends StatelessWidget {
  const _CatalogFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      _FailureBanner(message: message, onRetry: onRetry);
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          border: Border.all(color: colorScheme.error),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colorScheme.onErrorContainer,
            ),
            Text(message),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _EmptyRates extends StatelessWidget {
  const _EmptyRates();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('empty-rates'),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(
            Icons.add_chart_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Добавьте валюту, чтобы увидеть её курс.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
