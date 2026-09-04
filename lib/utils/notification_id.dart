/// Derives a stable, well-distributed 31-bit notification id from a
/// task id string.
///
/// Previously call sites used Dart's built-in `String.hashCode`
/// directly. That's fine for in-memory use, but it's not a documented,
/// stable algorithm — its distribution/behavior isn't guaranteed
/// across Dart versions, and collisions between two different task
/// ids (however rare) would silently make one task's alarm overwrite
/// another's. This uses a standard FNV-1a hash instead, masked into
/// the positive 32-bit range Android notification ids expect.
int notificationIdForTaskId(String taskId) {
  const int fnvPrime = 0x01000193;
  int hash = 0x811C9DC5;

  for (final codeUnit in taskId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }

  // Keep it a positive 31-bit value — some platform notification APIs
  // don't handle negative ids well.
  return hash & 0x7FFFFFFF;
}
