import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persiste únicamente el refresh token (sessionId+secret, DATA_MODEL.md §3)
/// entre reinicios de la app — el access token vive solo en memoria (estado
/// de Riverpod), nunca en disco, dada su vida corta (SECURITY.md §6).
class SecureTokenStorage {
  static const _sessionIdKey = 'refresh_session_id';
  static const _secretKey = 'refresh_secret';

  final FlutterSecureStorage _storage;

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveRefreshToken({required String sessionId, required String secret}) async {
    await _storage.write(key: _sessionIdKey, value: sessionId);
    await _storage.write(key: _secretKey, value: secret);
  }

  Future<({String sessionId, String secret})?> readRefreshToken() async {
    final sessionId = await _storage.read(key: _sessionIdKey);
    final secret = await _storage.read(key: _secretKey);
    if (sessionId == null || secret == null) {
      return null;
    }
    return (sessionId: sessionId, secret: secret);
  }

  Future<void> clear() async {
    await _storage.delete(key: _sessionIdKey);
    await _storage.delete(key: _secretKey);
  }
}
