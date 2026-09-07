import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'theme_location.dart';

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
    return await result.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}
