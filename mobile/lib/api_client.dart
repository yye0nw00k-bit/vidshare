import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class VidShareApi {
  static const _secureStorage = FlutterSecureStorage();
  static const _baseUrlKey = 'vidshare_api_base_url';
  static const _tokenKey = 'vidshare_api_token';
  static const _configuredUrl = String.fromEnvironment(
    'VIDSHARE_API_URL',
    defaultValue: '',
  );

  String _baseUrl = '';
  String? _token;

  String get baseUrl => _baseUrl;
  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> initialize() async {
    _baseUrl = (await _secureStorage.read(key: _baseUrlKey) ??
            _configuredUrl)
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    _token = await _secureStorage.read(key: _tokenKey);
  }

  Future<void> setBaseUrl(String value) async {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        !['https', 'http'].contains(parsed.scheme)) {
      throw const ApiException('올바른 서버 주소를 입력해주세요. 예: https://vidshare.onrender.com');
    }
    if (parsed.scheme != 'https' &&
        parsed.host != 'localhost' &&
        parsed.host != '10.0.2.2' &&
        parsed.host != '127.0.0.1') {
      throw const ApiException('실제 서버 주소는 HTTPS를 사용해야 합니다.');
    }
    _baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
    await _secureStorage.write(key: _baseUrlKey, value: _baseUrl);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (_baseUrl.isEmpty) {
      throw const ApiException('먼저 VidShare 서버 주소를 입력해주세요.');
    }
    return Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (hasToken) headers['Authorization'] = 'Bearer $_token';
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload = {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // A proxy or HTML error page should not crash the app's JSON decoder.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = payload['error']?.toString() ??
          '서버 요청에 실패했습니다. (\${response.statusCode})';
      throw ApiException(message, statusCode: response.statusCode);
    }
    return payload;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final response = await http
          .get(_uri(path, query), headers: _headers())
          .timeout(const Duration(seconds: 35));
      return _decode(response);
    } on SocketException {
      throw const ApiException('서버에 연결할 수 없습니다. 인터넷과 서버 주소를 확인해주세요.');
    } on HttpException {
      throw const ApiException('네트워크 오류가 발생했습니다.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await http
          .post(
            _uri(path),
            headers: _headers(jsonBody: true),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 35));
      return _decode(response);
    } on SocketException {
      throw const ApiException('서버에 연결할 수 없습니다. 인터넷과 서버 주소를 확인해주세요.');
    } on HttpException {
      throw const ApiException('네트워크 오류가 발생했습니다.');
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await _post('/api/mobile/auth/login', body: {
      'username': username,
      'password': password,
    });
    await _saveAuth(result);
    return result['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final result = await _post('/api/mobile/auth/register', body: {
      'username': username,
      'password': password,
    });
    await _saveAuth(result);
    return result['user'] as Map<String, dynamic>;
  }

  Future<void> _saveAuth(Map<String, dynamic> result) async {
    final token = result['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('서버에서 로그인 토큰을 받지 못했습니다.');
    }
    _token = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<Map<String, dynamic>> me() async {
    final result = await _get('/api/mobile/auth/me');
    return result['user'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      if (hasToken) await _post('/api/mobile/auth/logout');
    } finally {
      _token = null;
      await _secureStorage.delete(key: _tokenKey);
    }
  }

  Future<List<Map<String, dynamic>>> videos({
    String feed = 'home',
    String query = '',
  }) async {
    final params = <String, String>{'feed': feed, 'limit': '40'};
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    final result = await _get('/api/mobile/videos', query: params);
    final items = result['videos'];
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> video(int id) async {
    final result = await _get('/api/mobile/videos/$id');
    return Map<String, dynamic>.from(result['video'] as Map);
  }

  Future<Map<String, dynamic>> toggleLike(int id) =>
      _post('/api/mobile/videos/$id/like');

  Future<Map<String, dynamic>> toggleSubscribe(int channelId) =>
      _post('/api/mobile/channels/$channelId/subscribe');

  Future<Map<String, dynamic>> addComment(int videoId, String body) =>
      _post('/api/mobile/videos/$videoId/comments', body: {'body': body});

  Future<Map<String, dynamic>> uploadVideo({
    required String path,
    required String filename,
    required String title,
    required String description,
  }) async {
    if (!hasToken) throw const ApiException('로그인이 필요합니다.');
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/mobile/videos'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['title'] = title;
    request.fields['description'] = description;
    request.files.add(await http.MultipartFile.fromPath(
      'video',
      path,
      filename: filename,
    ));

    try {
      final streamed = await request.send().timeout(
        const Duration(minutes: 15),
      );
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on SocketException {
      throw const ApiException('업로드 중 서버 연결이 끊어졌습니다.');
    } on HttpException {
      throw const ApiException('영상 업로드 중 네트워크 오류가 발생했습니다.');
    }
  }
}
