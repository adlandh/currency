import 'rate_cache.dart';

RateCacheStore createRateCacheStore() => const _MemoryRateCacheStore();

class _MemoryRateCacheStore implements RateCacheStore {
  const _MemoryRateCacheStore();

  @override
  String? read() => null;

  @override
  void write(String value) {}
}
