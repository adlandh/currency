import 'package:web/web.dart';

import 'rate_cache.dart';

RateCacheStore createRateCacheStore() => BrowserRateCacheStore();

// Кэш — только оптимизация: ошибки хранилища не показываются пользователю.
class BrowserRateCacheStore implements RateCacheStore {
  @override
  String? read() {
    try {
      return window.localStorage.getItem(rateCacheKey);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String value) {
    try {
      window.localStorage.setItem(rateCacheKey, value);
    } catch (_) {}
  }
}
