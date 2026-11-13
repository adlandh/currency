import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:intl/intl.dart';

import 'conversion.dart';
import 'exchange_rates.dart';
import 'observability.dart';
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
  // Загрузка, заменившая незавершённое «Обновить», наследует обход кэша,
  // иначе ответ обновления отбрасывается и остаются прежние курсы из кэша.
  bool _forcePending = false;
  int _addMenuVersion = 0;

  @override
  void initState() {
    super.initState();
    try {
      _savedPreferences = widget.preferencesStore.read();
      _amountController.text = _savedPreferences?.amount ?? '1';
    } catch (error, stack) {
      unawaited(reportError(error, stack, 'preferences.read', once: true));
      _preferencesNotice = 'Не удалось восстановить настройки. Используются значения по умолчанию.';
    }
    unawaited(_loadCurrencies());
  }

  @override
  void dispose() {
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
    } catch (error) {
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = _errorMessage(error);
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

  Future<void> _loadTableRates({
    bool refresh = false,
    bool force = false,
  }) async {
    final base = _base;
    final request = ++_tableRequest;
    final requested = _externalTargets();
    force = _forcePending = force || _forcePending;
    if (requested.isEmpty) {
      _forcePending = false;
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
      final rates = await widget.api.fetchRates(base, requested, force: force);
      if (!_tableRequestIsCurrent(request, requested)) return;
      final current = _externalTargets();
      setState(() {
        _tableLoading = false;
        _tableRates = {for (final code in current) code: ?rates[code]};
        _missingTableRates = current.difference(rates.keys.toSet());
      });
    } catch (error) {
      if (!_tableRequestIsCurrent(request, requested)) return;
      final current = _externalTargets();
      setState(() {
        _tableLoading = false;
        if (refresh && _tableRates.isNotEmpty) {
          _tableRefreshWarning = true;
          _missingTableRates = current.difference(_tableRates.keys.toSet());
        } else {
          _tableRates = const {};
          _missingTableRates = current;
          _tableError = _errorMessage(error);
        }
      });
    } finally {
      if (request == _tableRequest) _forcePending = false;
    }
  }

  // Неожиданные исключения уже зарегистрированы в traceOperation.
  String _errorMessage(Object error) => error is ExchangeRatesException
      ? error.message
      : 'Не удалось загрузить данные.';

  Set<String> _externalTargets() =>
      _targets.where((target) => target != _base).toSet();

  // Удаление не запускает запрос, поэтому последний ответ принимается,
  // пока он покрывает все текущие внешние цели.
  bool _tableRequestIsCurrent(int request, Set<String> requested) {
    return mounted &&
        request == _tableRequest &&
        requested.containsAll(_externalTargets());
  }

  Future<void> _refreshAll() async {
    if (_catalogError != null || _currencies.isEmpty) {
      await _loadCurrencies();
      return;
    }
    await _loadTableRates(refresh: true, force: true);
  }

  void _addTarget(String? value) {
    if (value == null || _targets.contains(value)) return;
    setState(() {
      _targets = [..._targets, value];
      _addMenuVersion++;
    });
    _persistRateTablePreferences();
    unawaited(_loadTableRates(refresh: true));
  }

  void _removeTarget(String value) {
    setState(() {
      _targets = _targets.where((code) => code != value).toList();
      _tableRates = Map.of(_tableRates)..remove(value);
      _missingTableRates = _missingTableRates.difference({value});
    });
    _persistRateTablePreferences();
    // Без внешних целей сбрасываем ошибки и отменяем незавершённый запрос.
    if (_externalTargets().isEmpty) unawaited(_loadTableRates());
  }

  // newIndex уже скорректирован под удалённый элемент (onReorderItem).
  void _reorderTarget(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final targets = List<String>.of(_targets);
    targets.insert(newIndex, targets.removeAt(oldIndex));
    setState(() => _targets = targets);
    _persistRateTablePreferences();
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
    } catch (error, stack) {
      unawaited(reportError(error, stack, 'preferences.write', once: true));
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
    // Список строк — сливер прокрутки страницы: так перетаскивание у края
    // экрана само прокручивает страницу.
    return Scaffold(
      body: SafeArea(
        child: Scrollbar(
          child: CustomScrollView(
            primary: true,
            // ponytail: строим всю страницу, как прежний SingleChildScrollView:
            // иначе строки за экраном недоступны для Tab и диктора. Валют
            // десятки, а не тысячи; при росте — вернуть ленивую отрисовку.
            scrollCacheExtent: const ScrollCacheExtent.pixels(1e6),
            slivers: [
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  // Колонка шириной до 1040, по центру.
                  final side = math.max(
                    horizontalPadding,
                    (constraints.crossAxisExtent - 1040) / 2,
                  );
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 40, side, 48),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
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
                                const SizedBox(height: 24),
                              ] else
                                const SizedBox(height: 24),
                              if (_catalogLoading)
                                const _CatalogLoading()
                              else if (_catalogError != null)
                                _FailureBanner(
                                  message: _catalogError!,
                                  onRetry: _loadCurrencies,
                                )
                              else if (_currencies.isEmpty)
                                _FailureBanner(
                                  message:
                                      'Источник не вернул доступные валюты.',
                                  onRetry: _loadCurrencies,
                                ),
                            ],
                          ),
                        ),
                        if (!_catalogLoading &&
                            _catalogError == null &&
                            _currencies.isNotEmpty)
                          ..._buildRates(context),
                      ],
                    ),
                  );
                },
              ),
            ],
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
    // Заголовок — подпись: главный элемент страницы — сумма.
    final title = Theme.of(context).textTheme.headlineSmall;
    // Иконки всегда в строке заголовка: Wrap уносил переключатель темы
    // на отдельную строку на телефоне.
    return Row(
      children: [
        Flexible(
          child: Text(
            'Курсы валют',
            style: MediaQuery.sizeOf(context).width < 600
                ? title?.copyWith(fontSize: 20, letterSpacing: -0.2)
                : title,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('refresh-button'),
          onPressed: _refreshAll,
          tooltip: 'Обновить',
          icon: _catalogLoading || _tableLoading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.refresh_rounded, size: 22),
        ),
        const SizedBox(width: 4),
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
                autofocus: preference == widget.themePreference,
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

  List<Widget> _buildRates(BuildContext context) {
    final amount = parseAmount(_amountController.text);
    final colors = Theme.of(context).colorScheme;
    final surface = Theme.of(context).brightness == Brightness.dark
        ? colors.surfaceContainerLow
        : colors.surface;
    // Общая дата показывается один раз под суммой; при разных датах
    // публикации каждая строка показывает свою.
    final dates = {for (final rate in _tableRates.values) rate.date};
    final commonDate = dates.length == 1 ? dates.single : null;
    UnderlineInputBorder underline(Color color, double width) =>
        UnderlineInputBorder(
          borderSide: BorderSide(color: color, width: width),
        );
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('amount-field'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontSize: MediaQuery.sizeOf(context).width < 600 ? 34 : 40,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: 'Сумма',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: 'Например, 3 000,50',
                hintStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                helperText: amount.status == AmountStatus.empty
                    ? 'Введите сумму'
                    : null,
                errorText: amount.status == AmountStatus.invalid
                    ? amount.error
                    : null,
                errorMaxLines: 3,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: underline(colors.primary, 2),
                enabledBorder: underline(colors.primary, 2),
                focusedBorder: underline(colors.primary, 3),
                errorBorder: underline(colors.error, 2),
                focusedErrorBorder: underline(colors.error, 3),
                suffixIconConstraints: const BoxConstraints(),
                suffixIcon: Container(
                  margin: const EdgeInsets.only(left: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _base,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
              onChanged: (_) {
                setState(() {});
                if (parseAmount(_amountController.text).status ==
                    AmountStatus.valid) {
                  _persistRateTablePreferences();
                }
              },
            ),
            if (commonDate != null) ...[
              const SizedBox(height: 8),
              Text(
                'Курсы за ${DateFormat.yMMMMd('ru_RU').format(commonDate)}',
                key: const Key('rates-date'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            if (_tableError != null) ...[
              _FailureBanner(message: _tableError!, onRetry: _loadTableRates),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.crossAxisExtent < 900 ||
              MediaQuery.textScalerOf(context).scale(17) > 25;
          return DecoratedSliver(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            sliver: SliverPadding(
              // Отступ под рамку, как у Container с BoxDecoration.
              padding: const EdgeInsets.all(1),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (_targets.isNotEmpty)
                    SliverSemantics(
                      key: const Key('conversion-semantics'),
                      liveRegion: true,
                      container: true,
                      explicitChildNodes: true,
                      sliver: FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: SliverMainAxisGroup(
                          slivers: [
                            if (!compact)
                              SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        20,
                                        16,
                                        12,
                                        16,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text('Валюта'),
                                          ),
                                          SizedBox(width: 20),
                                          Expanded(
                                            flex: 4,
                                            child: Text('Курс'),
                                          ),
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
                                ),
                              ),
                            SliverReorderableList(
                              itemCount: _targets.length,
                              onReorderItem: _reorderTarget,
                              proxyDecorator: (child, _, _) => Material(
                                elevation: 6,
                                color: surface,
                                child: child,
                              ),
                              itemBuilder: (context, index) {
                                final code = _targets[index];
                                return _RowDragListener(
                                  key: Key('rate-row-$code'),
                                  index: index,
                                  // DecoratedSliver не обрезает детей: тень и фон
                                  // наведения обрезаются только по краям рамки.
                                  child: ClipRRect(
                                    clipper: _TableEdgeClipper(
                                      top: compact && index == 0,
                                    ),
                                    child: Column(
                                      children: [
                                        RateRow(
                                          currency: _currency(code)!,
                                          base: _base,
                                          rate: _tableRates[code],
                                          identity: code == _base,
                                          missing: _missingTableRates.contains(
                                            code,
                                          ),
                                          loading: _tableLoading,
                                          amount: amount,
                                          compact: compact,
                                          showDate: commonDate == null,
                                          onRemove: () => _removeTarget(code),
                                        ),
                                        const Divider(
                                          height: 1,
                                          indent: 20,
                                          endIndent: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Добавление — последняя строка таблицы.
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_targets.isEmpty) ...[
                          const _EmptyRates(),
                          const Divider(height: 1, indent: 20, endIndent: 20),
                        ],
                        CurrencyMenu(
                          key: ValueKey(
                            'add-$_addMenuVersion-${_currencies.length}',
                          ),
                          fieldKey: const Key('add-target-menu'),
                          label: 'Добавить валюту',
                          currencies: _currencies,
                          disabledCodes: _targets.toSet(),
                          onSelected: _addTarget,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tableRefreshWarning) ...[
              const SizedBox(height: 12),
              const _InlineNotice(
                icon: Icons.info_outline_rounded,
                text: 'Не удалось обновить. Показаны предыдущие курсы.',
              ),
            ],
            if (_targets.length == _currencies.length) ...[
              const SizedBox(height: 12),
              const Text('Все валюты уже добавлены.'),
            ],
            const SizedBox(height: 18),
            Text(
              'Источник: Frankfurter. Ежедневные справочные курсы; банковские комиссии не учитываются.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ];
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
          leadingIcon: Icon(
            Icons.add_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          // Без рамки: поле — строка таблицы, рамку даёт сама таблица.
          inputDecorationTheme: InputDecorationTheme(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
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

/// Обрезает строку по бокам рамки таблицы, а сверху — только у первой
/// строки без шапки (со скруглением). Между строками тень наведения
/// и подъём на 1 px остаются видны поверх соседей; снизу таблицу
/// замыкает строка добавления, поэтому низ не обрезается.
class _TableEdgeClipper extends CustomClipper<RRect> {
  const _TableEdgeClipper({required this.top});

  /// Запас под тень наведения (blur 10 + сдвиг 3).
  static const _overflow = 20.0;
  static const _radius = Radius.circular(11); // 12 у рамки минус 1 px толщины.

  final bool top;

  @override
  RRect getClip(Size size) => RRect.fromLTRBAndCorners(
    0,
    top ? 0 : -_overflow,
    size.width,
    size.height + _overflow,
    topLeft: top ? _radius : Radius.zero,
    topRight: top ? _radius : Radius.zero,
  );

  @override
  bool shouldReclip(_TableEdgeClipper old) => old.top != top;
}

/// Начинает перетаскивание строки: мышью — сразу при движении с зажатой
/// кнопкой, касанием — после удержания, чтобы не мешать прокрутке страницы.
// ponytail: у мыши порог сдвига при удержании 1 px, и отложенный старт
// срывался от дрожания руки; поэтому для мыши старт немедленный.
class _RowDragListener extends StatelessWidget {
  const _RowDragListener({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) =>
        SliverReorderableList.maybeOf(context)?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: event.kind == PointerDeviceKind.mouse
              ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
              : DelayedMultiDragGestureRecognizer(debugOwner: this),
        ),
    child: child,
  );
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
    this.showDate = true,
    required this.onRemove,
  });

  /// Показывать дату курса в строке (когда нет общей даты над таблицей).
  final bool showDate;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
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
          boxShadow: _hovered && !isDark
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
        padding: widget.compact
            ? const EdgeInsets.fromLTRB(20, 14, 4, 14)
            : const EdgeInsets.fromLTRB(20, 18, 12, 18),
        child: _content(context),
      ),
    );
  }

  /// На телефоне текст строки крупнее (+4 px), чтобы читался без очков;
  /// широкая таблица остаётся с размерами темы.
  TextStyle? _sized(TextStyle? style, double compactSize) =>
      widget.compact ? style?.copyWith(fontSize: compactSize) : style;

  Widget _content(BuildContext context) {
    final details = _details(context);
    final colors = Theme.of(context).colorScheme;
    final muted = _sized(Theme.of(context).textTheme.bodyMedium, 19);
    final code = Text(
      widget.currency.code,
      style: _sized(Theme.of(context).textTheme.titleMedium, 21),
    );
    final currencyName = Text(widget.currency.name, style: muted);
    final actions = SizedBox.square(
      dimension: 48,
      child: IconButton(
        key: Key('remove-${widget.currency.code}'),
        onPressed: widget.onRemove,
        tooltip: 'Удалить ${widget.currency.code}',
        // Тихий крестик: красным становится только под указателем и в фокусе.
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? colors.error
                : colors.onSurfaceVariant,
          ),
        ),
        icon: const Icon(Icons.close_rounded, size: 20),
      ),
    );
    if (widget.compact) {
      // Главное — сумма в валюте строки; обратный пересчёт и курс — тише.
      // Подпись направления стоит в одной линии со своей суммой, чтобы
      // при переносе они не разъезжались. Wrap роняет правую часть на
      // свою линию, когда пара не помещается (длинная сумма, крупный
      // текст), — без переполнения.
      Widget line(Widget left, Widget right) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [left, right],
      );
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                line(code, _result(context)),
                currencyName,
                details,
                const SizedBox(height: 4),
                line(
                  Text(
                    '${widget.currency.code} → ${widget.base}',
                    style: muted,
                  ),
                  _result(context, reverse: true),
                ),
              ],
            ),
          ),
          actions,
        ],
      );
    }
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [code, const SizedBox(height: 2), currencyName],
    );
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
        actions,
      ],
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
      result,
      key: Key(
        '${reverse ? 'reverse' : 'conversion'}-result-${widget.currency.code}',
      ),
      semanticsLabel: 'Результат конвертации $from → $to: $result',
      textAlign: TextAlign.right,
      // ponytail: при крупном системном тексте результат растёт не выше
      // прежних 48 px (24 px × 200%), иначе строка на 360 px выше экрана.
      textScaler: widget.compact
          ? MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 48 / 34)
          : null,
      // Оба результата одного размера; прямой выделен полужирным,
      // обратный — обычным начертанием.
      style:
          (reverse
                  ? Theme.of(context).textTheme.bodyLarge
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
                fontSize: widget.compact ? 34 : 20,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
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
    final muted = _sized(Theme.of(context).textTheme.bodyMedium, 19);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          key: Key('rate-${widget.currency.code}'),
          style:
              (widget.compact ? muted : Theme.of(context).textTheme.bodyLarge)
                  ?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
        ),
        if (!widget.identity && widget.rate != null && widget.showDate) ...[
          const SizedBox(height: 4),
          Text(
            'За ${DateFormat.yMMMMd('ru_RU').format(widget.rate!.date)}',
            style: muted,
          ),
        ],
        if (widget.identity) ...[
          const SizedBox(height: 4),
          Text('Тождественный курс', style: muted),
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
    // Рамку даёт таблица: пустое состояние — её первая строка.
    return Padding(
      key: const Key('empty-rates'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
