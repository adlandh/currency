import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'theme_location.dart';
import 'observability.dart';

Future<ThemeLocation?> getThemeLocation() async {
  final result = Completer<ThemeLocation?>();
  try {
    window.navigator.geolocation.getCurrentPosition(
      ((GeolocationPosition position) {
        if (!result.isCompleted) {
          final location = (
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
          );
          result.complete(validThemeLocation(location) ? location : null);
        }
      }).toJS,
      ((GeolocationPositionError _) {
        if (!result.isCompleted) result.complete(null);
      }).toJS,
      PositionOptions(
        enableHighAccuracy: false,
        timeout: 10000,
        maximumAge: 300000,
      ),
    );
    // Ожидание разрешения ограничивает внешний таймаут в main.dart.
    return await result.future;
  } catch (error, stack) {
    unawaited(reportError(error, stack, 'theme.location', once: true));
    return null;
  }
}
