import { REQUIRE_PERMISSION_KEY } from '../../common/decorators/require-permission.decorator';
import { ActivitiesController } from './activities.controller';
import { ActividadCompleta } from './activity.presenter';
import {
  ParcelaDeCampana,
  comprobarDetalle,
  comprobarQueNoEsFuturo,
  kilosCosechados,
  nutrienteKgHa,
  resolverDestinos,
  volumenM3,
} from './activity.rules';
import { calcularResumen } from './campaign-summary';
import { presentarDetalle } from './campaign.presenter';

/**
 * Actividades del cuaderno sin base de datos (BACKLOG.md #60, fase 3): las
 * reglas de coherencia y los números del resumen. Lo que depende de la base
 * (triggers, consultas, auditoría) va en
 * `test/integration/campaign-activities.spec.ts`.
 */
describe('Actividades', () => {
  describe('coherencia del detalle', () => {
    it('un riego no lleva datos de tratamiento', () => {
      expect(() =>
        comprobarDetalle(
          'irrigation',
          { phytosanitary: { products: [{ productName: 'Cobre' }] } },
          'alta',
        ),
      ).toThrow(/no lleva "phytosanitary"/);
    });

    it('una labor sin decir cuál no se entiende', () => {
      expect(() => comprobarDetalle('field_work', {}, 'alta')).toThrow(/qué labor/);
    });

    it('un abonado dice qué se aplicó: el producto o el tipo de material', () => {
      expect(() => comprobarDetalle('fertilization', { fertilization: {} }, 'alta')).toThrow(
        /qué se ha aplicado/,
      );
      expect(() =>
        comprobarDetalle(
          'fertilization',
          { fertilization: { materialType: 'solid_manure' } },
          'alta',
        ),
      ).not.toThrow();
    });

    it('un número sin unidad no significa nada', () => {
      expect(() => comprobarDetalle('irrigation', { irrigation: { amount: 18 } }, 'alta')).toThrow(
        /valor y su unidad/,
      );
      expect(() =>
        comprobarDetalle(
          'phytosanitary',
          { phytosanitary: { products: [{ productName: 'Cobre', doseUnit: 'kg_ha' }] } },
          'alta',
        ),
      ).toThrow(/"Cobre"/);
    });

    it('un riego sin cantidad se puede apuntar: se completa después', () => {
      expect(() => comprobarDetalle('irrigation', {}, 'alta')).not.toThrow();
    });
  });

  describe('a qué parcela y unidad va cada destino', () => {
    const deLaCampana: ParcelaDeCampana[] = [
      { cropUnitId: 'u1', parcelId: 'norte', parcelName: 'Norte', cropName: 'Aguacate', areaHa: 2 },
      { cropUnitId: 'u1', parcelId: 'sur', parcelName: 'Sur', cropName: 'Aguacate', areaHa: 1 },
      { cropUnitId: 'u2', parcelId: 'sur', parcelName: 'Sur', cropName: 'Tomate', areaHa: 0.5 },
    ];

    it('si la parcela está en una sola unidad, no hace falta decirla', () => {
      expect(resolverDestinos([{ parcelId: 'norte' }], deLaCampana)).toEqual([
        { cropUnitId: 'u1', parcelId: 'norte', areaHa: null, effectiveAreaHa: 2 },
      ]);
    });

    it('si está en dos, hay que elegir', () => {
      expect(() => resolverDestinos([{ parcelId: 'sur' }], deLaCampana)).toThrow(
        /"Sur" está en más de una unidad/,
      );
      expect(
        resolverDestinos([{ parcelId: 'sur', cropUnitId: 'u2' }], deLaCampana)[0].effectiveAreaHa,
      ).toBe(0.5);
    });

    it('una parcela de fuera de la campaña no vale', () => {
      expect(() => resolverDestinos([{ parcelId: 'otra' }], deLaCampana)).toThrow(
        /no es de esta campaña/,
      );
    });

    it('no más superficie de la que la parcela tiene en la campaña', () => {
      expect(() =>
        resolverDestinos([{ parcelId: 'sur', cropUnitId: 'u2', areaHa: 1 }], deLaCampana),
      ).toThrow(/no hay 1 ha de Tomate/);
    });
  });

  describe('valores normalizados', () => {
    it('18 m³/ha en 0,85 ha son 15,3 m³', () => {
      expect(volumenM3(18, 'm3_ha', 0.85)).toBe(15.3);
      expect(volumenM3(2500, 'l', 1)).toBe(2.5);
      expect(volumenM3(null, null, 1)).toBeNull();
    });

    it('kg de N por hectárea desde la dosis y la riqueza', () => {
      // 320 kg/ha de un 15-15-15: 48 kg de N por hectárea.
      expect(nutrienteKgHa(320, 'kg_ha', 15, 2)).toBe(48);
      expect(nutrienteKgHa(0.5, 't_ha', 20, 2)).toBe(100);
      // 640 kg en total sobre 2 ha: lo mismo que 320 kg/ha.
      expect(nutrienteKgHa(640, 'kg', 15, 2)).toBe(48);
    });

    it('una dosis en litros no se pasa a kg: haría falta la densidad y no se inventa', () => {
      expect(nutrienteKgHa(300, 'l_ha', 15, 2)).toBeNull();
    });

    it('la cosecha en toneladas se pasa a kg; en unidades, no', () => {
      expect(kilosCosechados(38.2, 't')).toBe(38200);
      expect(kilosCosechados(500, 'units')).toBeNull();
    });

    it('no se registra el futuro (con un día de margen por los husos)', () => {
      const ahora = new Date('2026-09-22T10:00:00Z');
      expect(() => comprobarQueNoEsFuturo(new Date('2026-09-23'), ahora)).not.toThrow();
      expect(() => comprobarQueNoEsFuturo(new Date('2026-09-25'), ahora)).toThrow(/no ha pasado/);
    });
  });

  describe('resumen de la campaña', () => {
    const campana = presentarDetalle({
      id: 'c1',
      name: 'Aguacate Hass · 2026',
      status: 'active',
      managementMode: 'simple',
      installation: { id: 'f1', name: 'Finca' },
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
          expectedYieldKgHa: 10000,
          parcels: [
            {
              parcelId: 'p1',
              areaHa: null,
              parcel: { name: 'Norte', areaM2: 40000, deletedAt: null },
            },
          ],
        },
      ],
    } as never);

    const destino = {
      cropUnitId: 'u1',
      parcelId: 'p1',
      areaHa: null,
      cropUnitParcel: { areaHa: null, parcel: { name: 'Norte', areaM2: 40000 } },
    };
    const actividad = (
      tipo: string,
      fecha: string,
      detalle: Record<string, unknown> = {},
    ): ActividadCompleta =>
      ({
        type: tipo,
        startDate: new Date(fecha),
        createdAt: new Date(fecha),
        targets: [destino],
        irrigation: null,
        fertilization: null,
        harvest: null,
        phytosanitaryProducts: [],
        ...detalle,
      }) as never;

    it('suma lo que se sabe y cuenta aparte lo que no', () => {
      const resumen = calcularResumen(campana, [
        actividad('irrigation', '2026-09-01', { irrigation: { volumeM3: 72 } }),
        actividad('irrigation', '2026-09-08', { irrigation: { volumeM3: null } }),
        actividad('fertilization', '2026-08-01', {
          fertilization: { nKgHa: 48, p2o5KgHa: 48, k2oKgHa: 48 },
        }),
        actividad('harvest', '2026-09-20', { harvest: { quantityKg: 38200 } }),
      ]);

      expect(resumen.irrigation).toEqual({
        count: 2,
        volumeM3: 72,
        volumeM3PerHa: 18,
        withoutVolume: 1,
      });
      // 48 kg/ha sobre las 4 ha de la campaña.
      expect(resumen.fertilization?.nKg).toBe(192);
      expect(resumen.fertilization?.nKgHa).toBe(48);
      expect(resumen.harvest?.yieldKgHa).toBe(9550);
      expect(resumen.harvest?.expectedYieldKgHa).toBe(10000);
      expect(resumen.cropUnits[0].yieldKgHa).toBe(9550);
      expect(resumen.lastActivity).toEqual({ type: 'harvest', date: '2026-09-20' });
    });

    it('sin actividades de un tipo, su apartado no sale: ni un cero que parezca una medida', () => {
      const resumen = calcularResumen(campana, []);

      expect(resumen.irrigation).toBeNull();
      expect(resumen.fertilization).toBeNull();
      expect(resumen.phytosanitary).toBeNull();
      expect(resumen.harvest).toBeNull();
      expect(resumen.lastActivity).toBeNull();
      expect(resumen.cropUnits[0].harvestKg).toBeNull();
    });
  });

  it('leer pide campaigns.read; registrar, cambiar y borrar, campaigns.record', () => {
    const permisoDe = (metodo: keyof ActivitiesController) =>
      Reflect.getMetadata(REQUIRE_PERMISSION_KEY, ActivitiesController.prototype[metodo]);

    expect(permisoDe('list')).toBe('campaigns.read');
    expect(permisoDe('findOne')).toBe('campaigns.read');
    expect(permisoDe('summary')).toBe('campaigns.read');
    expect(permisoDe('create')).toBe('campaigns.record');
    expect(permisoDe('update')).toBe('campaigns.record');
    expect(permisoDe('remove')).toBe('campaigns.record');
  });
});
