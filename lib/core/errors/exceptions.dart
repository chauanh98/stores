class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Bạn không có quyền thực hiện thao tác này.']);

  @override
  String toString() => 'UnauthorizedException: $message';
}

class ValidationException implements Exception {
  final String message;
  const ValidationException(this.message);

  @override
  String toString() => 'ValidationException: $message';
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException(this.message);

  @override
  String toString() => 'NotFoundException: $message';
}
