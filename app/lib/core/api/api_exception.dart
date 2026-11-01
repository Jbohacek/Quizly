import 'package:dio/dio.dart';

import '../strings.dart';

/// A failed API call: a ProblemDetails response (api.md §1.1) or a network failure ([status] null).
class ApiException implements Exception {
  const ApiException({required this.status, required this.code, this.title, this.retryAfter, this.errors = const {}});

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      return ApiException(status: null, code: e.type == DioExceptionType.cancel ? 'cancelled' : 'network');
    }
    final data = response.data;
    final retryAfter = int.tryParse(response.headers.value('retry-after') ?? '');
    final status = response.statusCode ?? 0;
    if (data is Map<String, dynamic> && data['code'] is String) {
      return ApiException(
        status: status,
        code: data['code'] as String,
        title: data['title'] as String?,
        retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
        errors: {
          if (data['errors'] case final Map<String, dynamic> errors)
            for (final e in errors.entries)
              if (e.value case final List<dynamic> messages) e.key: [for (final m in messages) '$m'],
        },
      );
    }
    return ApiException(
      status: status,
      code: status >= 500 ? 'serverError' : 'http$status',
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }

  /// HTTP status; null when the server wasn't reached (timeout, no connection).
  final int? status;

  /// Stable error code from the server (`invalidCredentials`, `rateLimited`, …), or `network`.
  final String code;

  /// Czech message from the server, safe to show as is.
  final String? title;
  final Duration? retryAfter;

  /// Field errors of a `validation` problem: camelCase field → Czech messages.
  final Map<String, List<String>> errors;

  /// The first message for [field], if any.
  String? fieldError(String field) => errors[field]?.firstOrNull;

  bool get isNetwork => status == null;

  /// Worth retrying the same request later (api.md §11.6).
  bool get isTransient => isNetwork || (status ?? 0) >= 500 || status == 429;

  /// A Czech message for the user.
  String get message {
    if (isNetwork) return S.networkError;
    if (status == 429) return S.rateLimited(retryAfter?.inSeconds ?? 60);
    if (title != null && title!.isNotEmpty) return title!;
    return (status ?? 0) >= 500 ? S.serverError : S.loadFailed;
  }

  @override
  String toString() => 'ApiException($status, $code)';
}
