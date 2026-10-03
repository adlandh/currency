import 'rate_cache.dart';
import 'rate_cache_store_stub.dart'
    if (dart.library.js_interop) 'rate_cache_store_web.dart'
    as platform;

RateCacheStore createRateCacheStore() => platform.createRateCacheStore();
