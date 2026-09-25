import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super('Сессия завершена. Войдите снова.');
}

class ConflictException extends ApiException {
  const ConflictException(this.current)
    : super('Профиль изменён на другом устройстве.');
  final Profile current;
}

class Profile {
  const Profile({required this.displayName, required this.revision});
  final String displayName;
  final int revision;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    displayName: json['displayName'] as String,
    revision: json['revision'] as int,
  );
}

class LoginResult {
  const LoginResult(this.token, this.expiresAt);
  final String token;
  final DateTime expiresAt;
}

class ApiClient {
  ApiClient({required Uri baseUri, http.Client? httpClient})
    : _baseUri = baseUri,
      _http = httpClient ?? http.Client() {
    if (baseUri.scheme != 'https' &&
        !(kDebugMode && baseUri.scheme == 'http')) {
      throw ArgumentError('HTTPS is required outside debug builds');
    }
  }

  final Uri _baseUri;
  final http.Client _http;

  Uri _uri(String path) => _baseUri.resolve(path);

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const ApiException('Нет связи с сервером.');
    } on HttpException {
      throw const ApiException('Нет связи с сервером.');
    } on TimeoutException {
      throw const ApiException('Сервер не ответил вовремя.');
    } on http.ClientException {
      throw const ApiException('Нет связи с сервером.');
    }
  }

  Map<String, dynamic> _body(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException('Сервер вернул некорректный ответ.');
    } on TypeError {
      throw const ApiException('Сервер вернул некорректный ответ.');
    }
  }

  void _expectSuccess(http.Response response) {
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _body(response)['error'] as String? ?? 'Ошибка сервера.',
      );
    }
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
  };

  Future<LoginResult> login(String username, String password) async {
    final response = await _send(
      () => _http.post(
        _uri('/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ),
    );
    if (response.statusCode == 401) {
      throw const ApiException('Неверный логин или пароль.');
    }
    _expectSuccess(response);
    final json = _body(response);
    return LoginResult(
      json['token'] as String,
      DateTime.parse(json['expiresAt'] as String),
    );
  }

  Future<void> validateSession(String token) async {
    final response = await _send(
      () => _http.get(_uri('/v1/auth/session'), headers: _headers(token)),
    );
    _expectSuccess(response);
  }

  Future<void> logout(String token) async {
    final response = await _send(
      () => _http.post(_uri('/v1/auth/logout'), headers: _headers(token)),
    );
    _expectSuccess(response);
  }

  Future<Profile> getProfile(String token) async {
    final response = await _send(
      () => _http.get(_uri('/v1/profile'), headers: _headers(token)),
    );
    _expectSuccess(response);
    return Profile.fromJson(_body(response));
  }

  Future<Profile> updateProfile(
    String token,
    String displayName,
    int revision,
  ) async {
    final response = await _send(
      () => _http.put(
        _uri('/v1/profile'),
        headers: {..._headers(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'displayName': displayName, 'revision': revision}),
      ),
    );
    if (response.statusCode == 409) {
      throw ConflictException(
        Profile.fromJson(_body(response)['profile'] as Map<String, dynamic>),
      );
    }
    _expectSuccess(response);
    return Profile.fromJson(_body(response));
  }

  void close() => _http.close();
}
