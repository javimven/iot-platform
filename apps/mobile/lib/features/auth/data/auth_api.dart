import '../../../core/api/api_client.dart';
import 'auth_models.dart';

/// Llamadas HTTP crudas a `/auth/*` y `/me` (OPENAPI.yaml). Sin lógica de
/// estado — eso vive en `AuthController`.
class AuthApi {
  final ApiClient _client;

  AuthApi(this._client);

  Future<LoginResponse> login({required String email, required String password}) async {
    final json = await _client.postJson('/auth/login', body: {
      'email': email,
      'password': password,
    });
    return LoginResponse.fromJson(json);
  }

  Future<AuthSuccessResult> selectOrganization({
    required String preAuthToken,
    required String organizationId,
  }) async {
    final json = await _client.postJson('/auth/select-organization', body: {
      'preAuthToken': preAuthToken,
      'organizationId': organizationId,
    });
    return AuthSuccessResult.fromJson(json);
  }

  Future<AuthSuccessResult> refresh({required String sessionId, required String secret}) async {
    final json = await _client.postJson('/auth/refresh', body: {
      'sessionId': sessionId,
      'secret': secret,
    });
    return AuthSuccessResult.fromJson(json);
  }

  Future<void> logout({required String sessionId}) async {
    await _client.post('/auth/logout', body: {'sessionId': sessionId});
  }

  Future<MeProfile> me() async {
    final json = await _client.getJson('/me');
    return MeProfile.fromJson(json);
  }
}
