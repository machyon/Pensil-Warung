/// A non-2xx answer in the API error envelope.
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
    this.requestId,
  });

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final String? requestId;

  @override
  String toString() => 'ApiException($status $code, request $requestId)';
}

/// Socket error or timeout: the request never got an answer.
class NetworkException implements Exception {
  const NetworkException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// Text to show for a failed call: the server's Indonesian message, or a network line.
String messageOf(Object e) => e is ApiException ? e.message : 'Tidak ada koneksi. Coba lagi.';
