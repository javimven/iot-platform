import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/directory/data/directory_models.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/organization/data/organization_models.dart';
import 'package:iot_platform_app/features/stations/application/stations_controller.dart';
import 'package:iot_platform_app/features/stations/data/stations_api.dart';

/// ADR-0007: el Admin de plataforma ve en "Estaciones" las de todas las
/// organizaciones y pide los datos de cada una por la ruta de plataforma de
/// SU organización. Un miembro sigue por la ruta de miembro.
class _FakeStationsApi implements StationsApi {
  final latestReadingsCalls = <(String, String?)>[];

  static OrganizationProfile _organization(String id, String name) => OrganizationProfile(
        id: id,
        slug: id,
        name: name,
        contactEmail: 'contacto@example.com',
        status: 'active',
        createdAt: DateTime.utc(2026, 9, 1),
      );

  static Gateway _gateway(String id, String organizationId, String installationId) => Gateway(
        id: id,
        organizationId: organizationId,
        installationId: installationId,
        name: id,
        connectivityType: 'direct_nbiot',
        status: 'online',
        lastSeenAt: null,
      );

  @override
  Future<List<Gateway>> allGateways() async => [_gateway('gw-propia', 'org-a', 'inst-a')];

  @override
  Future<List<OrganizationProfile>> organizations() async =>
      [_organization('org-a', 'JMV Soluciones'), _organization('org-b', 'Finca Cliente')];

  @override
  Future<List<Gateway>> gatewaysOfOrganization(String organizationId) async => organizationId == 'org-a'
      ? [_gateway('gw-a', 'org-a', 'inst-a')]
      : [_gateway('gw-b', 'org-b', 'inst-b')];

  @override
  Future<List<Installation>> installationsOfOrganization(String organizationId) async => [
        Installation(
          id: organizationId == 'org-a' ? 'inst-a' : 'inst-b',
          name: 'Finca Norte',
          locationText: null,
          latitude: null,
          longitude: null,
          status: 'active',
        ),
      ];

  @override
  Future<List<LatestReading>> latestReadingsForGateway(String gatewayId, {String? organizationId}) async {
    latestReadingsCalls.add((gatewayId, organizationId));
    return const [];
  }
}

void main() {
  ProviderContainer container({required bool platformAdmin, required _FakeStationsApi api}) {
    final c = ProviderContainer(overrides: [
      stationsApiProvider.overrideWithValue(api),
      stationsAcrossOrganizationsProvider.overrideWithValue(platformAdmin),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('el Admin de plataforma lista las estaciones de todas las organizaciones', () async {
    final c = container(platformAdmin: true, api: _FakeStationsApi());
    final sub = c.listen(allGatewaysProvider, (_, __) {});
    final gateways = await c.read(allGatewaysProvider.future);
    expect(gateways.map((g) => g.id), ['gw-a', 'gw-b']);
    sub.close();
  });

  test('el Admin de plataforma agrupa por finca, con su organización aparte', () async {
    final c = container(platformAdmin: true, api: _FakeStationsApi());
    final sub = c.listen(stationGroupNamesProvider, (_, __) {});
    final names = await c.read(stationGroupNamesProvider.future);
    expect(names, {
      'inst-a': (farm: 'Finca Norte', organization: 'JMV Soluciones'),
      'inst-b': (farm: 'Finca Norte', organization: 'Finca Cliente'),
    });
    sub.close();
  });

  test('el Admin de plataforma pide las lecturas por la organización de cada estación', () async {
    final api = _FakeStationsApi();
    final c = container(platformAdmin: true, api: api);
    final subGateways = c.listen(allGatewaysProvider, (_, __) {});
    await c.read(allGatewaysProvider.future);
    final subReadings = c.listen(gatewayLatestReadingsProvider('gw-b'), (_, __) {});
    await c.read(gatewayLatestReadingsProvider('gw-b').future);
    expect(api.latestReadingsCalls, [('gw-b', 'org-b')]);
    subReadings.close();
    subGateways.close();
  });

  test('un miembro sigue por la ruta de miembro, sin organización explícita', () async {
    final api = _FakeStationsApi();
    final c = container(platformAdmin: false, api: api);
    final subGateways = c.listen(allGatewaysProvider, (_, __) {});
    expect((await c.read(allGatewaysProvider.future)).map((g) => g.id), ['gw-propia']);
    final subReadings = c.listen(gatewayLatestReadingsProvider('gw-propia'), (_, __) {});
    await c.read(gatewayLatestReadingsProvider('gw-propia').future);
    expect(api.latestReadingsCalls, [('gw-propia', null)]);
    subReadings.close();
    subGateways.close();
  });

  test('prefijo de rutas: vacío para un miembro, de plataforma con organización', () {
    expect(stationsPathPrefix(null), '');
    expect(stationsPathPrefix('org-b'), '/platform/organizations/org-b');
  });
}
