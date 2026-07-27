import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/auth_token_delegate.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';
import 'auth_state.dart';

/// Orquesta el flujo de autenticación completo (API_DESIGN.md §3) y expone
/// el token vigente a `ApiClient` a través de `AuthTokenDelegate` — es el
/// único lugar de la app que conoce el estado de sesión.
class AuthController extends StateNotifier<AuthState> implements AuthTokenDelegate {
  final AuthApi _authApi;
  final SecureTokenStorage _storage;

  AuthController(this._authApi, this._storage) : super(AuthState.initial());

  @override
  String? get accessToken => state.accessToken;

  /// Se llama una vez al arrancar la app: intenta restaurar la sesión desde
  /// el refresh token persistido (sin pedir email/contraseña de nuevo).
  Future<void> bootstrap() async {
    final stored = await _storage.readRefreshToken();
    if (stored == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    final refreshed = await _refreshWith(stored.sessionId, stored.secret);
    if (!refreshed) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _authApi.login(email: email, password: password);
      if (response.success != null) {
        await _enterAuthenticated(response.success!);
      } else {
        final selection = response.needsOrgSelection!;
        state = state.copyWith(
          status: AuthStatus.needsOrgSelection,
          preAuthToken: selection.preAuthToken,
          organizations: selection.organizations,
          isLoading: false,
        );
      }
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.title);
    }
  }

  Future<void> selectOrganization(String organizationId) async {
    if (state.preAuthToken == null) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final result = await _authApi.selectOrganization(
        preAuthToken: state.preAuthToken!,
        organizationId: organizationId,
      );
      await _enterAuthenticated(result);
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.title);
    }
  }

  Future<void> logout() async {
    final sessionId = state.refreshSessionId;
    if (sessionId != null) {
      try {
        await _authApi.logout(sessionId: sessionId);
      } on ApiException {
        // Si falla la llamada, igualmente se limpia el estado local — no
        // tiene sentido dejar al usuario "atrapado" en la app por un error de red.
      }
    }
    await forceLogout();
  }

  @override
  Future<bool> refreshSession() async {
    final sessionId = state.refreshSessionId;
    final secret = state.refreshSecret;
    if (sessionId == null || secret == null) {
      return false;
    }
    return _refreshWith(sessionId, secret);
  }

  @override
  Future<void> forceLogout() async {
    await _storage.clear();
    state = AuthState.initial().copyWith(status: AuthStatus.unauthenticated);
  }

  Future<bool> _refreshWith(String sessionId, String secret) async {
    try {
      final result = await _authApi.refresh(sessionId: sessionId, secret: secret);
      await _enterAuthenticated(result);
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> _enterAuthenticated(AuthSuccessResult result) async {
    // El access token debe estar disponible en `state` ANTES de llamar a
    // `/me` (ApiClient lo lee de aquí para la cabecera Authorization).
    state = state.copyWith(
      status: AuthStatus.authenticated,
      accessToken: result.accessToken,
      refreshSessionId: result.refreshSessionId,
      refreshSecret: result.refreshSecret,
      isLoading: false,
    );
    await _storage.saveRefreshToken(sessionId: result.refreshSessionId, secret: result.refreshSecret);

    final profile = await _authApi.me();
    state = state.copyWith(
      organizationId: profile.activeOrganizationId,
      roleCode: profile.roleCode,
      isPlatformAdmin: profile.isPlatformAdmin,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) => SecureTokenStorage());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController(ref.watch(authApiProvider), ref.watch(secureTokenStorageProvider));
  // Conecta el ApiClient con este controlador como fuente del token — se
  // hace aquí (no en el constructor de ApiClient) para evitar un ciclo de
  // dependencias entre ambos providers.
  ref.watch(apiClientProvider).authDelegate = controller;
  return controller;
});
