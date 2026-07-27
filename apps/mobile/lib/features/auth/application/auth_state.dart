import '../data/auth_models.dart';

enum AuthStatus { initial, unauthenticated, needsOrgSelection, authenticated }

/// Estado de sesión de la app (ARCHITECTURE.md §6). `needsOrgSelection`
/// corresponde exactamente al `AuthOrgSelection` del backend (API_DESIGN.md §3).
class AuthState {
  final AuthStatus status;
  final bool isLoading;
  final String? errorMessage;

  // needsOrgSelection
  final String? preAuthToken;
  final List<OrganizationOption> organizations;

  // authenticated
  final String? accessToken;
  final String? refreshSessionId;
  final String? refreshSecret;
  final String? organizationId;
  final String? roleCode;
  final bool isPlatformAdmin;

  const AuthState({
    required this.status,
    this.isLoading = false,
    this.errorMessage,
    this.preAuthToken,
    this.organizations = const [],
    this.accessToken,
    this.refreshSessionId,
    this.refreshSecret,
    this.organizationId,
    this.roleCode,
    this.isPlatformAdmin = false,
  });

  factory AuthState.initial() => const AuthState(status: AuthStatus.initial);

  /// Nota: `errorMessage` no se conserva entre llamadas (siempre `null` salvo
  /// que se pase explícitamente) — a diferencia del resto de campos, es
  /// intencional: un mensaje de error es transitorio y no debe sobrevivir a
  /// una transición de estado no relacionada.
  ///
  /// Limitación conocida: al usar `??` para el resto de campos, no hay forma
  /// de pasar explícitamente `null` a `organizationId`/`roleCode`/`preAuthToken`
  /// para *borrar* un valor previo (se conservaría el anterior) — no supone
  /// un problema con los usos actuales de este método (siempre se llama con
  /// un valor no nulo cuando de verdad hace falta cambiarlos, o se sustituye
  /// el estado entero vía `AuthState.initial()` para reiniciarlos). Si en el
  /// futuro hiciera falta borrar uno de estos campos de forma explícita, este
  /// `copyWith` necesitaría el patrón de valor centinela para distinguir
  /// "no proporcionado" de "puesto a null".
  AuthState copyWith({
    AuthStatus? status,
    bool? isLoading,
    String? errorMessage,
    String? preAuthToken,
    List<OrganizationOption>? organizations,
    String? accessToken,
    String? refreshSessionId,
    String? refreshSecret,
    String? organizationId,
    String? roleCode,
    bool? isPlatformAdmin,
  }) {
    return AuthState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      preAuthToken: preAuthToken ?? this.preAuthToken,
      organizations: organizations ?? this.organizations,
      accessToken: accessToken ?? this.accessToken,
      refreshSessionId: refreshSessionId ?? this.refreshSessionId,
      refreshSecret: refreshSecret ?? this.refreshSecret,
      organizationId: organizationId ?? this.organizationId,
      roleCode: roleCode ?? this.roleCode,
      isPlatformAdmin: isPlatformAdmin ?? this.isPlatformAdmin,
    );
  }
}
