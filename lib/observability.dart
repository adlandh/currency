import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _operations = {
  'currencies.load',
  'rates.load',
  'preferences.read',
  'preferences.write',
  'theme.read',
  'theme.write',
  'theme.calculate',
  'theme.location',
};
final _reportedOperations = <String>{};

bool validSentryDsn(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isNotEmpty &&
      !uri.userInfo.contains(':') &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.pathSegments.isNotEmpty &&
      RegExp(r'^\d+$').hasMatch(uri.pathSegments.last);
}

double sentryTraceRate(String value) {
  final rate = double.tryParse(value);
  return rate != null && rate.isFinite && rate >= 0 && rate <= 1 ? rate : 0;
}

Future<void> runWithObservability(
  void Function() runApp, {
  String dsn = const String.fromEnvironment('SENTRY_DSN'),
  Future<void> Function(
        void Function(SentryFlutterOptions), {
        AppRunner? appRunner,
      })
      initialize =
      SentryFlutter.init,
}) async {
  _reportedOperations.clear();
  var started = false;
  void start() {
    if (started) return;
    started = true;
    runApp();
  }

  if (!validSentryDsn(dsn)) {
    start();
    return;
  }
  try {
    await initialize((options) {
      configureObservability(options);
      options.dsn = dsn;
    }, appRunner: start);
  } catch (_) {
    // Ошибка диагностики не должна препятствовать запуску приложения.
    try {
      await Sentry.close();
    } catch (_) {}
    start();
  }
}

void configureObservability(SentryOptions options) {
  const environment = String.fromEnvironment('SENTRY_ENVIRONMENT');
  const release = String.fromEnvironment('SENTRY_RELEASE');
  options.environment = environment.isEmpty
      ? (kReleaseMode ? 'production' : 'development')
      : environment;
  if (release.isNotEmpty) options.release = release;
  options.tracesSampleRate = sentryTraceRate(
    const String.fromEnvironment(
      'SENTRY_TRACES_SAMPLE_RATE',
      defaultValue: '0.1',
    ),
  );
  options.sendDefaultPii = false;
  options.enablePrintBreadcrumbs = false;
  options.enableLogs = false;
  options.beforeBreadcrumb = (_, _) => null;
  options.beforeSend = (event, _) => cleanSentryEvent(event);
  options.beforeSendTransaction = (event, _) {
    if (!_operations.contains(event.transaction)) return null;
    cleanSentryEvent(event);
    event.spans.clear();
    event.measurements.clear();
    return event;
  };
  if (options is SentryFlutterOptions) {
    options.enableAutoPerformanceTracing = false;
    options.enableUserInteractionBreadcrumbs = false;
    options.enableAutoSessionTracking = false;
    options.attachScreenshot = false;
    // ignore: experimental_member_use
    options.attachViewHierarchy = false;
    options.replay.sessionSampleRate = 0;
    options.replay.onErrorSampleRate = 0;
  }
}

SentryEvent cleanSentryEvent(SentryEvent event) {
  final trace = event.contexts.trace;
  event.contexts = Contexts();
  if (trace != null) {
    event.contexts.trace = SentryTraceContext(
      traceId: trace.traceId,
      spanId: trace.spanId,
      parentSpanId: trace.parentSpanId,
      status: trace.status,
      operation: _operations.contains(trace.operation)
          ? trace.operation
          : 'app',
    );
  }
  event.user = null;
  event.request = null;
  event.breadcrumbs = null;
  event.message = null;
  event.threads = null;
  event.serverName = null;
  event.culprit = null;
  event.logger = null;
  event.fingerprint = null;
  event.debugMeta = null;
  // ignore: deprecated_member_use
  event.extra = null;
  event.transaction = _operations.contains(event.transaction)
      ? event.transaction
      : null;
  event.tags = {
    if (_operations.contains(event.tags?['operation']))
      'operation': event.tags!['operation']!,
    if (RegExp(r'^[1-5]\d\d$').hasMatch(event.tags?['http.status_code'] ?? ''))
      'http.status_code': event.tags!['http.status_code']!,
  };
  event.exceptions = event.exceptions
      ?.map(
        (error) => SentryException(
          type: error.type,
          value: 'Техническая ошибка',
          mechanism: error.mechanism == null
              ? null
              : Mechanism(
                  type: error.mechanism!.type,
                  handled: error.mechanism!.handled,
                ),
          stackTrace: error.stackTrace == null
              ? null
              : SentryStackTrace(
                  frames: error.stackTrace!.frames
                      .map(
                        (frame) => SentryStackFrame(
                          fileName: _cleanPath(frame.fileName),
                          absPath: _cleanPath(frame.absPath),
                          function: frame.function,
                          lineNo: frame.lineNo,
                          colNo: frame.colNo,
                          inApp: frame.inApp,
                        ),
                      )
                      .toList(),
                ),
        ),
      )
      .toList();
  return event;
}

String? _cleanPath(String? path) => path?.split(RegExp(r'[?#]')).first;

Future<void> reportError(
  Object error,
  StackTrace stack,
  String operation, {
  bool once = false,
  ISentrySpan? span,
  int? httpStatus,
}) async {
  if (!Sentry.isEnabled || (once && !_reportedOperations.add(operation))) {
    return;
  }
  try {
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        scope.setTag('operation', operation);
        if (httpStatus != null) scope.setTag('http.status_code', '$httpStatus');
        if (span != null) scope.span = span;
      },
    );
  } catch (_) {
    // Не отправляем ошибки самого транспорта обратно в Sentry.
  }
}

Future<T> traceOperation<T>(
  String operation,
  Future<T> Function() action,
) async {
  final span = Sentry.startTransaction(operation, operation);
  try {
    final result = await action();
    span.status = const SpanStatus.ok();
    return result;
  } catch (error, stack) {
    span.status = const SpanStatus.internalError();
    if (error is ObservedException) {
      await reportError(
        error.cause ?? error,
        error.causeStack ?? stack,
        operation,
        span: span,
        httpStatus: error.httpStatus,
      );
    } else {
      await reportError(error, stack, operation, span: span);
    }
    rethrow;
  } finally {
    await _finish(span);
  }
}

Future<void> _finish(ISentrySpan span) async {
  try {
    await span.finish();
  } catch (_) {}
}

class ObservedException implements Exception {
  const ObservedException(
    this.message, {
    this.cause,
    this.causeStack,
    this.httpStatus,
  });
  final String message;
  final Object? cause;
  final StackTrace? causeStack;
  final int? httpStatus;
  @override
  String toString() => message;
}
