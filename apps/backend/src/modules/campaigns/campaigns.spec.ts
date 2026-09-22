import { ForbiddenException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { REQUIRE_FEATURE_KEY } from '../../common/decorators/require-feature.decorator';
import { REQUIRE_PERMISSION_KEY } from '../../common/decorators/require-permission.decorator';
import { ROLE_PERMISSIONS } from '../../common/permissions/permissions';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CampaignAccess } from './campaign-access';
import { CampanaCompleta, nombreAutomatico, presentarDetalle } from './campaign.presenter';
import { CampaignsController } from './campaigns.controller';
import { comprobarParcelasSinRepetir, comprobarSuperficies } from './crop-unit.rules';
import { CropsController } from './crops.controller';
import { CampaignCreateDto } from './dto/campaign.dto';

/**
 * Lo de Campañas que no necesita una base de datos (BACKLOG.md #60). Los
 * servicios, con sus consultas y triggers, se prueban contra Postgres real en
 * `test/integration/campaigns-service.spec.ts`.
 */
describe('Campañas', () => {
  describe('validación de la entrada', () => {
    const alta = (cambios: Record<string, unknown> = {}) =>
      plainToInstance(CampaignCreateDto, {
        managementMode: 'simple',
        startDate: '2026-02-03',
        cropUnits: [
          { cropId: 'aguacate', parcels: [{ parcelId: '0b6c1f8e-4b1e-4c52-9d2a-6c1f0b1e2d3a' }] },
        ],
        ...cambios,
      });

    async function errores(dto: object) {
      const lista = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
      return lista.map((e) => e.property);
    }

    it('un alta mínima es válida: finca, parcela, cultivo y fecha', async () => {
      await expect(errores(alta())).resolves.toEqual([]);
    });

    it('las fechas van sin hora y tienen que existir', async () => {
      await expect(errores(alta({ startDate: '2026-02-30' }))).resolves.toEqual(['startDate']);
      await expect(errores(alta({ startDate: '2026-2-3' }))).resolves.toEqual(['startDate']);
      await expect(errores(alta({ startDate: '2026-02-03T10:00:00Z' }))).resolves.toEqual([
        'startDate',
      ]);
    });

    it('sin cultivo del catálogo, el nombre del cultivo es obligatorio', async () => {
      const sinCultivo = alta({
        cropUnits: [{ parcels: [{ parcelId: '0b6c1f8e-4b1e-4c52-9d2a-6c1f0b1e2d3a' }] }],
      });
      await expect(errores(sinCultivo)).resolves.toEqual(['cropUnits']);
    });

    it('una unidad sin parcelas no vale: una campaña sin sitio no sirve', async () => {
      const sinParcelas = alta({ cropUnits: [{ cropId: 'aguacate', parcels: [] }] });
      await expect(errores(sinParcelas)).resolves.toEqual(['cropUnits']);
    });

    it('el perfil del cuaderno solo acepta sus preguntas', async () => {
      const conOtraCosa = alta({
        managementMode: 'complete',
        notebookProfile: { usesFertigation: true, cumpleLaLey: true },
      });
      await expect(errores(conOtraCosa)).resolves.toEqual(['notebookProfile']);
    });
  });

  describe('nombre automático', () => {
    it('cultivo, variedad y año', () => {
      expect(nombreAutomatico('Aguacate', 'Hass', new Date('2026-02-03'), undefined)).toBe(
        'Aguacate Hass · 2026',
      );
    });

    it('si cruza de año, como se dice en el campo: 2026/27', () => {
      expect(
        nombreAutomatico('Olivo', undefined, new Date('2026-10-01'), new Date('2027-02-28')),
      ).toBe('Olivo · 2026/27');
    });
  });

  describe('superficies', () => {
    const campana = {
      id: 'c1',
      name: 'Aguacate Hass · 2026',
      status: 'active',
      managementMode: 'simple',
      installation: { id: 'f1', name: 'Finca Norte' },
      startDate: new Date('2026-02-03'),
      expectedEndDate: null,
      endDate: null,
      notes: null,
      notebookProfile: {},
      declaredProductionKg: null,
      closingNotes: null,
      closedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      cropUnits: [
        {
          id: 'u1',
          cropId: 'aguacate',
          cropName: 'Aguacate',
          variety: 'Hass',
          areaHa: null,
          parcels: [
            // Entera: 1,2 ha.
            {
              parcelId: 'p1',
              areaHa: null,
              parcel: { name: 'Norte', areaM2: 12000, deletedAt: null },
            },
            // Media parcela declarada.
            {
              parcelId: 'p2',
              areaHa: 0.5,
              parcel: { name: 'Sur', areaM2: 20000, deletedAt: null },
            },
          ],
        },
        {
          id: 'u2',
          cropId: null,
          cropName: 'Tomate',
          variety: null,
          // Declarada a mano: manda sobre la suma de parcelas.
          areaHa: 0.3,
          parcels: [
            {
              parcelId: 'p2',
              areaHa: null,
              parcel: { name: 'Sur', areaM2: 20000, deletedAt: null },
            },
          ],
        },
      ],
    } as unknown as CampanaCompleta;

    it('la parcela entera cuenta entera, la declarada lo declarado, y la unidad declarada manda', () => {
      const detalle = presentarDetalle(campana);

      expect(detalle.cropUnits[0].parcelsAreaHa).toBe(1.7);
      expect(detalle.cropUnits[1].effectiveAreaHa).toBe(0.3);
      expect(detalle.areaHa).toBe(2);
    });

    it('una parcela en dos unidades cuenta una vez al contar parcelas', () => {
      expect(presentarDetalle(campana).parcelCount).toBe(2);
    });

    it('en la tarjeta, el cultivo con su variedad', () => {
      expect(presentarDetalle(campana).crops).toEqual(['Aguacate Hass', 'Tomate']);
    });
  });

  describe('reglas de las unidades de cultivo', () => {
    it('la misma parcela no puede ir dos veces', () => {
      expect(() =>
        comprobarParcelasSinRepetir([{ parcelId: 'p1' }, { parcelId: 'p1', areaHa: 1 }]),
      ).toThrow(/dos veces/);
    });

    it('se admite un poco más que la parcela dibujada, pero no el doble', () => {
      const deLaFinca = new Map([['p1', { name: 'Norte', areaHa: 1 }]]);
      expect(() =>
        comprobarSuperficies([{ parcelId: 'p1', areaHa: 1.01 }], deLaFinca),
      ).not.toThrow();
      expect(() => comprobarSuperficies([{ parcelId: 'p1', areaHa: 2 }], deLaFinca)).toThrow(
        /"Norte"/,
      );
    });
  });

  describe('alcance por finca', () => {
    const acceso = (asignadas: string[]) =>
      new CampaignAccess({
        memberInstallationScope: {
          findMany: jest
            .fn()
            .mockResolvedValue(asignadas.map((installationId) => ({ installationId }))),
        },
      } as unknown as PrismaService);

    it('quien solo tiene unas fincas no toca campañas de otra', async () => {
      await expect(
        acceso(['finca-1']).asegurarFincaEnAlcance(
          { sub: 'u', type: 'access', organizationId: 'o', roleCode: 'technician', memberId: 'm' },
          'finca-2',
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('el administrador de la organización ve todas', async () => {
      await expect(
        acceso(['finca-1']).asegurarFincaEnAlcance(
          { sub: 'u', type: 'access', organizationId: 'o', roleCode: 'org_admin', memberId: 'm' },
          'finca-2',
        ),
      ).resolves.toBeUndefined();
    });

    it('una campaña cerrada no se modifica', () => {
      expect(() => acceso([]).asegurarAbierta({ status: 'closed' })).toThrow(/reábrela/);
      expect(() => acceso([]).asegurarAbierta({ status: 'active' })).not.toThrow();
    });
  });

  describe('protección de la API', () => {
    it('todo exige la función contratada, también el catálogo de cultivos', () => {
      expect(Reflect.getMetadata(REQUIRE_FEATURE_KEY, CampaignsController)).toEqual(['campaigns']);
      expect(Reflect.getMetadata(REQUIRE_FEATURE_KEY, CropsController)).toEqual(['campaigns']);
    });

    it('cada ruta pide su permiso, y ninguna se queda sin él', () => {
      const permisoDe = (metodo: keyof CampaignsController) =>
        Reflect.getMetadata(REQUIRE_PERMISSION_KEY, CampaignsController.prototype[metodo]);

      expect(permisoDe('list')).toBe('campaigns.read');
      expect(permisoDe('findOne')).toBe('campaigns.read');
      expect(permisoDe('create')).toBe('campaigns.create');
      expect(permisoDe('update')).toBe('campaigns.update');
      expect(permisoDe('upgrade')).toBe('campaigns.update');
      expect(permisoDe('addCropUnit')).toBe('campaigns.update');
      expect(permisoDe('close')).toBe('campaigns.close');
      expect(permisoDe('reopen')).toBe('campaigns.close');
      expect(permisoDe('remove')).toBe('campaigns.delete');
    });

    it('el operario registra lo que hace pero no monta ni cierra campañas', () => {
      expect(ROLE_PERMISSIONS.operator).toEqual(
        expect.arrayContaining(['campaigns.read', 'campaigns.record']),
      );
      for (const permiso of [
        'campaigns.create',
        'campaigns.update',
        'campaigns.close',
        'campaigns.delete',
      ]) {
        expect(ROLE_PERMISSIONS.operator).not.toContain(permiso);
      }
      expect(ROLE_PERMISSIONS.technician).not.toContain('campaigns.delete');
      expect(ROLE_PERMISSIONS.read_only).toEqual(expect.arrayContaining(['campaigns.read']));
      expect(ROLE_PERMISSIONS.read_only).not.toContain('campaigns.record');
    });
  });
});
