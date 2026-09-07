import 'theme_location_stub.dart'
    if (dart.library.js_interop) 'theme_location_web.dart'
    as platform;

typedef ThemeLocation = ({double latitude, double longitude});

bool validThemeLocation(ThemeLocation location) =>
    location.latitude.isFinite &&
    location.longitude.isFinite &&
    location.latitude.abs() <= 90 &&
    location.longitude.abs() <= 180;

Future<ThemeLocation?> getThemeLocation() => platform.getThemeLocation();
