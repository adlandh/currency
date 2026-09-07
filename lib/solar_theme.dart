import 'package:nrel_spa/nrel_spa.dart';

import 'theme_location.dart';

bool? isSolarDay(DateTime instant, ThemeLocation location) {
  if (!validThemeLocation(location)) return null;
  try {
    final result = getSpa(
      instant.toUtc(),
      location.latitude,
      location.longitude,
      0,
      pressure: 0,
      functionCode: spaZa,
    );
    if (!result.zenith.isFinite) return null;
    return 90 - result.zenith >= -0.833;
  } catch (_) {
    return null;
  }
}
