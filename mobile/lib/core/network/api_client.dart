import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/session.dart';
import '../config/app_config.dart';
import '../storage/prefs.dart';
import '../../core/i18n/i18n.dart';

/// An error from the API, already unwrapped from {"error": {code, message, details}}.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'error', this.status, this.details});

  final String message;
  final String code;
  final int? status;
  final Object? details;

  /// First field error if the server sent validation details, else the message.
  String get friendly {
    final d = details;
    if (d is Map && d.isNotEmpty) {
      final first = d.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first is String) return first;
    }
    return message;
  }

  @override
  String toString() => friendly;
}

class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> get access => _read('access_token');
  Future<String?> get refresh => _read('refresh_token');

  // The encrypted store comes back empty on some phones after a restart or update, which logged people
  // out. A copy in the app's private settings keeps them signed in until they log out themselves.
  Future<String?> _read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    } catch (_) {
      // Unreadable encrypted store: use the copy.
    }
    return Prefs.get(key);
  }

  Future<void> save(String access, String refresh) async {
    await Prefs.set('access_token', access);
    await Prefs.set('refresh_token', refresh);
    try {
      await _storage.write(key: 'access_token', value: access);
      await _storage.write(key: 'refresh_token', value: refresh);
    } catch (_) {
      // The copy above is enough.
    }
  }

  Future<void> clear() async {
    await Prefs.remove('access_token');
    await Prefs.remove('refresh_token');
    await Prefs.remove('user');
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}

/// Thin wrapper around Dio: adds the JWT, refreshes it once on 401, and turns errors into [ApiException].
class ApiClient {
  ApiClient(this.tokens, {this.onSessionExpired})
      : dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          // Generous: a free-plan server can take about a minute to wake up on the first request.
          connectTimeout: const Duration(seconds: 70),
          receiveTimeout: const Duration(seconds: 70),
        )) {
    dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokens.access;
        if (token != null && options.extra['auth'] != false) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final retried = error.requestOptions.extra['retried'] == true;
        if (error.response?.statusCode == 401 && !retried && await _refresh()) {
          final options = error.requestOptions..extra['retried'] = true;
          options.headers['Authorization'] = 'Bearer ${await tokens.access}';
          try {
            return handler.resolve(await dio.fetch(options));
          } on DioException catch (e) {
            return handler.next(e);
          }
        }
        handler.next(error);
      },
    ));
  }

  final Dio dio;
  final TokenStorage tokens;
  final void Function()? onSessionExpired;

  Future<bool> _refresh() async {
    final refresh = await tokens.refresh;
    if (refresh == null) return false;
    try {
      final response = await Dio(BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 70),
        receiveTimeout: const Duration(seconds: 70),
      )).post('/auth/refresh/', data: {'refresh': refresh});
      await tokens.save(response.data['access'], response.data['refresh'] ?? refresh);
      return true;
    } on DioException catch (e) {
      // Log out only when the server rejects the token. No internet, or the free server still waking
      // up (502/503), must not throw the person out.
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        await tokens.clear();
        onSessionExpired?.call();
      }
      return false;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, [Object? data]) => _send(() => dio.post(path, data: data));

  Future<dynamic> patch(String path, Object? data) => _send(() => dio.patch(path, data: data));

  Future<dynamic> delete(String path) => _send(() => dio.delete(path));

  /// GET a paginated list and return just the results.
  Future<List<dynamic>> list(String path, {Map<String, dynamic>? query}) async {
    final data = await get(path, query: query);
    return data is Map ? (data['results'] as List) : data as List;
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) =>
      query == null ? null : (Map.of(query)..removeWhere((_, v) => v == null || v == ''));

  Future<dynamic> _send(Future<Response> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final error = data['error'] as Map;
        throw ApiException(
          error['message']?.toString() ?? tr('कुछ गड़बड़ हुई'),
          code: error['code']?.toString() ?? 'error',
          status: e.response?.statusCode,
          details: error['details'],
        );
      }
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw ApiException(tr('इंटरनेट कनेक्शन चेक करें'), code: 'network');
      }
      throw ApiException(tr('सर्वर से जवाब नहीं मिला ({0})', [e.response?.statusCode ?? '-']), status: e.response?.statusCode);
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiProvider = Provider<ApiClient>((ref) {
  // An expired refresh token logs the user out (read lazily to avoid a provider cycle).
  return ApiClient(
    ref.watch(tokenStorageProvider),
    onSessionExpired: () => ref.read(sessionProvider.notifier).signOutLocally(),
  );
});
