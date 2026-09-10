/// Exception thrown when an operation requires cloud connectivity
/// (e.g. generating a sequential Job No. or Invoice No.) but the device
/// is offline or the server is unreachable.
class OfflineException implements Exception {
  final String message;
  const OfflineException([this.message = 'Internet connection required to complete this action.']);

  @override
  String toString() => 'OfflineException: $message';
}

/// Exception thrown when an insertion is blocked due to a duplicate primary key
/// or unique constraint violation (e.g. another device claimed the number first).
class DuplicateKeyException implements Exception {
  final String message;
  final dynamic conflictingKey;

  const DuplicateKeyException({
    required this.message,
    this.conflictingKey,
  });

  @override
  String toString() => 'DuplicateKeyException: $message (Key: $conflictingKey)';
}
