/// Espejo de `Organization` (OPENAPI.yaml, `GET/PATCH /organization`).
class OrganizationProfile {
  final String id;
  final String slug;
  final String name;
  final String contactEmail;
  final String status;
  final DateTime createdAt;

  const OrganizationProfile({
    required this.id,
    required this.slug,
    required this.name,
    required this.contactEmail,
    required this.status,
    required this.createdAt,
  });

  factory OrganizationProfile.fromJson(Map<String, dynamic> json) => OrganizationProfile(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        contactEmail: json['contactEmail'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Espejo de `OrganizationFeature` (`GET /organization/features`) — solo
/// `org_admin` puede leerlo (`PERMISSIONS.md` §14); nunca editable desde
/// aquí, solo el Admin de plataforma puede activarlo/desactivarlo.
class OrganizationFeature {
  final String featureCode;
  final bool enabled;
  final DateTime updatedAt;

  const OrganizationFeature({
    required this.featureCode,
    required this.enabled,
    required this.updatedAt,
  });

  factory OrganizationFeature.fromJson(Map<String, dynamic> json) => OrganizationFeature(
        featureCode: json['featureCode'] as String,
        enabled: json['enabled'] as bool,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// Espejo de `OrgChannelThreshold` (`GET/PUT /organization/channel-thresholds`)
/// — umbral por defecto de un tipo de canal para toda la organización; un
/// canal con umbral propio (Directorio IoT) lo sustituye. Hasta el
/// 2026-07-30 solo existía el `PUT` (`BACKLOG.md` #16).
class OrgChannelThreshold {
  final String channelTypeCode;
  final double? defaultMin;
  final double? defaultMax;
  final DateTime updatedAt;

  const OrgChannelThreshold({
    required this.channelTypeCode,
    required this.defaultMin,
    required this.defaultMax,
    required this.updatedAt,
  });

  factory OrgChannelThreshold.fromJson(Map<String, dynamic> json) => OrgChannelThreshold(
        channelTypeCode: json['channelTypeCode'] as String,
        defaultMin: (json['defaultMin'] as num?)?.toDouble(),
        defaultMax: (json['defaultMax'] as num?)?.toDouble(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
