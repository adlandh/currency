import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'conversion.dart';
import 'exchange_rates.dart';
import 'rate_table_preferences.dart';

class CurrencyPage extends StatefulWidget {
  const CurrencyPage({
    super.key,
    required this.api,
    required this.preferencesStore,
  });

  final ExchangeRatesApi api;
  final RateTablePreferencesStore preferencesStore;

  @override
  State<CurrencyPage> createState() => _CurrencyPageState();
}

class _CurrencyPageState extends State<CurrencyPage> {
  final _amountController = TextEditingController(text: '1');

  List<CurrencyInfo> _currencies = const [];
  List<String> _targets = const [];
  String? _base;
  String? _from;
  String? _to;

  bool _catalogLoading = true;
  String? _catalogError;
  Map<String, ExchangeRate> _tableRates = const {};
  Set<String> _missingTableRates = const {};
  bool _tableLoading = false;
  String? _tableError;
  bool _tableRefreshWarning = false;
  ExchangeRate? _conversionRate;
  bool _conversionLoading = false;
  String? _conversionError;
  bool _conversionRefreshWarning = false;
  RateTablePreferences? _savedPreferences;
  String? _preferencesNotice;

  int _catalogRequest = 0;
  int _tableRequest = 0;
  int _conversionRequest = 0;
  int _addMenuVersion = 0;

  @override
  void initState() {
    super.initState();
    try {
      _savedPreferences = widget.preferencesStore.read();
    } catch (_) {
      _preferencesNotice = 'Не удалось восстановить настройки. Используются значения по умолчанию.';
    }
    unawaited(_loadCurrencies());
  }

  @override
  void dispose() {
    _catalogRequest++;
    _tableRequest++;
    _conversionRequest++;
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
      final base = saved != null && codes.contains(saved.base)
          ? saved.base
          : _pick(codes, 'EUR');
      final from = _pick(codes, 'EUR');
      final to = _pick(codes, 'CZK', except: from);
      final targets = saved == null
          ? ['USD', 'CZK', 'GBP'].where(codes.contains).toList()
          : _availableUnique(saved.targets, codes);
      setState(() {
        _currencies = currencies;
        _catalogLoading = false;
        _base = base;
        _from = from;
        _to = to;
        _targets = targets;
        _tableRates = const {};
        _missingTableRates = const {};
        _conversionRate = null;
      });
      if (currencies.isNotEmpty) {
        _persistRateTablePreferences(clearNoticeOnSuccess: false);
        unawaited(_loadTableRates());
        unawaited(_loadConversionRate());
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

  String? _pick(Set<String> codes, String preferred, {String? except}) {
    if (codes.contains(preferred) && preferred != except) return preferred;
    for (final code in codes) {
      if (code != except) return code;
    }
    return except != null && codes.contains(except) ? except : null;
  }

  Future<void> _loadTableRates({bool refresh = false}) async {
    final base = _base;
    final targets = List<String>.of(_targets);
    final request = ++_tableRequest;
    if (base == null) return;
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
      if (!_tableRequestIsCurrent(request, base, targets)) return;
      setState(() {
        _tableLoading = false;
        _tableRates = rates;
        _missingTableRates = requested.difference(rates.keys.toSet());
      });
    } on ExchangeRatesException catch (error) {
      if (!_tableRequestIsCurrent(request, base, targets)) return;
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

  bool _tableRequestIsCurrent(int request, String base, List<String> targets) {
    return mounted &&
        request == _tableRequest &&
        base == _base &&
        _sameItems(targets, _targets);
  }

  bool _sameItems(List<String> left, List<String> right) =>
      left.length == right.length &&
      Iterable.generate(left.length)
          .every((index) => left[index] == right[index]);

  Future<void> _loadConversionRate({bool refresh = false}) async {
    final from = _from;
    final to = _to;
    final request = ++_conversionRequest;
    if (from == null || to == null) return;
    if (from == to) {
      setState(() {
        _conversionLoading = false;
        _conversionRate = null;
        _conversionError = null;
        _conversionRefreshWarning = false;
      });
      return;
    }

    setState(() {
      _conversionLoading = true;
      _conversionError = null;
      _conversionRefreshWarning = false;
      if (!refresh) _conversionRate = null;
    });

    try {
      final rates = await widget.api.fetchRates(from, [to]);
      if (!_conversionRequestIsCurrent(request, from, to)) return;
      final rate = rates[to];
      setState(() {
        _conversionLoading = false;
        _conversionRate = rate;
        if (rate == null) _conversionError = 'Курс недоступен.';
      });
    } on ExchangeRatesException catch (error) {
      if (!_conversionRequestIsCurrent(request, from, to)) return;
      setState(() {
        _conversionLoading = false;
        if (refresh && _conversionRate != null) {
          _conversionRefreshWarning = true;
        } else {
          _conversionRate = null;
          _conversionError = error.message;
        }
      });
    }
  }

  bool _conversionRequestIsCurrent(int request, String from, String to) =>
      mounted && request == _conversionRequest && from == _from && to == _to;

  Future<void> _refreshAll() async {
    if (_catalogError != null || _currencies.isEmpty) {
      await _loadCurrencies();
      return;
    }
    await Future.wait([
      _loadTableRates(refresh: true),
      _loadConversionRate(refresh: true),
    ]);
  }

  void _changeBase(String? value) {
    if (value == null || value == _base) return;
    setState(() => _base = value);
    _persistRateTablePreferences();
    unawaited(_loadTableRates());
  }

  void _changeFrom(String? value) {
    if (value == null || value == _from) return;
    setState(() => _from = value);
    unawaited(_loadConversionRate());
  }

  void _changeTo(String? value) {
    if (value == null || value == _to) return;
    setState(() => _to = value);
    unawaited(_loadConversionRate());
  }

  void _swapCurrencies() {
    if (_from == null || _to == null || _from == _to) return;
    setState(() {
      final previousFrom = _from;
      _from = _to;
      _to = previousFrom;
    });
    unawaited(_loadConversionRate());
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
    if (base == null) return;
    final preferences = RateTablePreferences(
      base: base,
      targets: List<String>.of(_targets),
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
                    else ...[
                      _buildConverter(context),
                      const SizedBox(height: 56),
                      _buildRates(context),
                    ],
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
    return Wrap(
      spacing: 24,
      runSpacing: 20,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Курсы валют',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Сравнивайте ежедневные справочные курсы и пересчитывайте суммы.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          key: const Key('refresh-button'),
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Обновить'),
        ),
      ],
    );
  }

  Widget _buildConverter(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5DFDA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A153D31),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0A153D31),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final form = _buildConversionForm(context);
          final result = _buildConversionResult(context);
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [form, const SizedBox(height: 28), result],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: form),
              const SizedBox(width: 64),
              Expanded(flex: 4, child: result),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConversionForm(BuildContext context) {
    final amount = parseAmount(_amountController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Конвертер', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Введите сумму и выберите направление.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
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
            errorText: amount.status == AmountStatus.invalid
                ? amount.error
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  CurrencyMenu(
                    key: ValueKey('from-${_currencies.length}'),
                    fieldKey: const Key('from-menu'),
                    label: 'Из валюты',
                    currencies: _currencies,
                    selectedCode: _from,
                    clearSelectionOnOpen: true,
                    onSelected: _changeFrom,
                  ),
                  const SizedBox(height: 16),
                  CurrencyMenu(
                    key: ValueKey('to-${_currencies.length}'),
                    fieldKey: const Key('to-menu'),
                    label: 'В валюту',
                    currencies: _currencies,
                    selectedCode: _to,
                    clearSelectionOnOpen: true,
                    onSelected: _changeTo,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('swap-currencies-button'),
              tooltip: 'Поменять валюты местами',
              onPressed: _from != null && _to != null && _from != _to
                  ? _swapCurrencies
                  : null,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConversionResult(BuildContext context) {
    final amount = parseAmount(_amountController.text);
    final sameCurrency = _from != null && _from == _to;
    final rate = sameCurrency ? 1.0 : _conversionRate?.rate;
    String? result;
    if (amount.status == AmountStatus.valid && rate != null && _to != null) {
      try {
        result = formatMoney(convertAmount(amount.value!, rate), _to!);
      } on FormatException {
        result = null;
      }
    }

    String status;
    if (amount.status == AmountStatus.empty) {
      status = 'Введите сумму';
    } else if (amount.status == AmountStatus.invalid) {
      status = 'Исправьте сумму';
    } else if (_conversionLoading && rate == null) {
      status = 'Получаем курс…';
    } else if (_conversionError != null && rate == null) {
      status = _conversionError!;
    } else {
      status = result ?? 'Не удалось рассчитать сумму.';
    }

    final rateLine = rate == null || _from == null || _to == null
        ? null
        : '1 $_from = ${formatRate(rate)} $_to';
    final dateLine = sameCurrency || _conversionRate == null
        ? null
        : 'Курс за ${DateFormat.yMMMMd('ru_RU').format(_conversionRate!.date)}';

    final semanticsLabel = [
      'Результат конвертации: $status',
      rateLine,
      dateLine,
      if (_conversionRefreshWarning)
        'Не удалось обновить. Показан предыдущий курс.',
    ].whereType<String>().join('. ');

    return Semantics(
      key: const Key('conversion-semantics'),
      liveRegion: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE9F2ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFB8CDC3)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Получится', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SelectableText(
                status,
                key: const Key('conversion-result'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: result == null ? 22 : 30,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (rateLine != null) ...[
                const SizedBox(height: 14),
                Text(rateLine, key: const Key('conversion-rate')),
              ],
              if (dateLine != null) ...[
                const SizedBox(height: 4),
                Text(dateLine, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (_conversionRefreshWarning) ...[
                const SizedBox(height: 12),
                const _InlineNotice(
                  icon: Icons.info_outline_rounded,
                  text: 'Не удалось обновить. Показан предыдущий курс.',
                ),
              ],
              if (_conversionError != null && rate == null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('retry-conversion'),
                  onPressed: _loadConversionRate,
                  child: const Text('Повторить'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRates(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Курсы относительно',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Выберите базу и валюты, которые хотите сравнить.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final menuWidth = constraints.maxWidth < 600
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: menuWidth,
                  child: CurrencyMenu(
                    key: ValueKey('base-$_base-${_currencies.length}'),
                    fieldKey: const Key('base-menu'),
                    label: 'Базовая валюта',
                    currencies: _currencies,
                    selectedCode: _base,
                    onSelected: _changeBase,
                  ),
                ),
                SizedBox(
                  width: menuWidth,
                  child: CurrencyMenu(
                    key: ValueKey('add-$_addMenuVersion-${_currencies.length}'),
                    fieldKey: const Key('add-target-menu'),
                    label: 'Добавить валюту',
                    currencies: _currencies,
                    disabledCodes: _targets.toSet(),
                    onSelected: _addTarget,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (_tableError != null)
          _FailureBanner(message: _tableError!, onRetry: _loadTableRates)
        else if (_targets.isEmpty)
          const _EmptyRates()
        else
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD5DFDA)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < _targets.length; index++) ...[
                  RateRow(
                    key: Key('rate-row-${_targets[index]}'),
                    currency: _currency(_targets[index])!,
                    base: _base!,
                    rate: _tableRates[_targets[index]],
                    identity: _targets[index] == _base,
                    missing: _missingTableRates.contains(_targets[index]),
                    loading: _tableLoading,
                    onRemove: () => _removeTarget(_targets[index]),
                  ),
                  if (index != _targets.length - 1)
                    const Divider(height: 1, indent: 20, endIndent: 20),
                ],
              ],
            ),
          ),
        if (_tableRefreshWarning) ...[
          const SizedBox(height: 12),
          const _InlineNotice(
            icon: Icons.info_outline_rounded,
            text: 'Не удалось обновить. Показаны предыдущие курсы.',
          ),
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

class CurrencyMenu extends StatefulWidget {
  const CurrencyMenu({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.currencies,
    required this.onSelected,
    this.selectedCode,
    this.disabledCodes = const {},
    this.clearSelectionOnOpen = false,
  });

  final Key fieldKey;
  final String label;
  final List<CurrencyInfo> currencies;
  final String? selectedCode;
  final Set<String> disabledCodes;
  final bool clearSelectionOnOpen;
  final ValueChanged<String?> onSelected;

  @override
  State<CurrencyMenu> createState() => _CurrencyMenuState();
}

class _CurrencyMenuState extends State<CurrencyMenu> {
  final _textController = TextEditingController();
  final _menuController = MenuController();
  late final FocusNode _focusNode;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKey);
    _focusNode.addListener(_restoreAfterFocusLoss);
  }

  @override
  void didUpdateWidget(CurrencyMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCode != widget.selectedCode) {
      _searching = false;
      _menuController.close();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_restoreAfterFocusLoss)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  void _startSearch() {
    if (!widget.clearSelectionOnOpen || _menuController.isOpen) return;
    _searching = true;
    _textController.clear();
  }

  void _restoreAfterFocusLoss() {
    if (!_focusNode.hasFocus) _restoreAfterMenuCloses();
  }

  void _restoreAfterMenuCloses() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_menuController.isOpen) _restoreSelection();
    });
  }

  void _restoreSelection() {
    if (!_searching) return;
    _searching = false;
    final label = widget.currencies
        .where((currency) => currency.code == widget.selectedCode)
        .map((currency) => currency.label)
        .firstOrNull;
    _textController.value = TextEditingValue(
      text: label ?? '',
      selection: TextSelection.collapsed(offset: label?.length ?? 0),
    );
  }

  void _select(String? value) {
    if (value == null) {
      _restoreSelection();
      return;
    }
    _searching = false;
    widget.onSelected(value);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (!widget.clearSelectionOnOpen || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _menuController.isOpen) {
      _menuController.close();
      _restoreSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab && _menuController.isOpen) {
      _menuController.close();
      _restoreSelection();
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) _startSearch();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) => _restoreAfterMenuCloses(),
      child: Listener(
        onPointerDown: (_) {
          if (_menuController.isOpen) {
            _restoreAfterMenuCloses();
          } else {
            _startSearch();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) => DropdownMenu<String>(
            key: widget.fieldKey,
            width: constraints.maxWidth,
            label: Text(widget.label),
            controller: _textController,
            focusNode: _focusNode,
            menuController: _menuController,
            initialSelection: widget.selectedCode,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            menuHeight: 360,
            leadingIcon: const Icon(Icons.search_rounded, size: 20),
            inputDecorationTheme: Theme.of(context).inputDecorationTheme,
            dropdownMenuEntries: widget.currencies
                .map(
                  (currency) => DropdownMenuEntry(
                    value: currency.code,
                    label: currency.label,
                    enabled: !widget.disabledCodes.contains(currency.code),
                  ),
                )
                .toList(),
            onSelected: _select,
          ),
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
    required this.onRemove,
  });

  final CurrencyInfo currency;
  final String base;
  final ExchangeRate? rate;
  final bool identity;
  final bool missing;
  final bool loading;
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
          color: _hovered ? const Color(0xFFF1F6F3) : Colors.transparent,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
            if (constraints.maxWidth < 600) {
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
                  details,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: name),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: details),
                const SizedBox(width: 8),
                remove,
              ],
            );
          },
        ),
      ),
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
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F2),
          border: Border.all(color: const Color(0xFFC97A7E)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFF8A272D)),
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
        Icon(icon, size: 18, color: const Color(0xFF5A675F)),
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
        border: Border.all(color: const Color(0xFFD5DFDA)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Icon(Icons.add_chart_rounded, color: Color(0xFF285C4D)),
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
