import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { REQUIRE_FEATURE_KEY } from '../../common/decorators/require-feature.decorator';
import { REQUIRE_PERMISSION_KEY } from '../../common/decorators/require-permission.decorator';
import { ActividadCompleta } from './activity.presenter';
import { ActivitiesController } from './activities.controller';
import { presentarDetalle } from './campaign.presenter';
import {
  NotebookEquipmentCreateDto,
  NotebookPersonCreateDto,
  NotebookPersonUpdateDto,
} from './dto/notebook.dto';
import {
  calcularCompletitud,
  CONJUNTO_DE_REGLAS,
  EntradaDeCompletitud,
} from './notebook-completeness';
import { NotebookController } from './notebook.controller';
import { presentarEquipo, presentarPersona } from './notebook.service';

/**
 * El cuaderno completo sin base de datos (fase 5 del #60): qué falta, por qué
 * y con qué fuente. Los catálogos contra Postgres real van en
 * `test/integration/notebook-catalog.spec.ts`.
 */

const FINCA_COMPLETA = { holderName: 'Ana Ruiz', holderNif: '12345678Z', regionCode: 'ES-AN' };

const PERFIL_RESPONDIDO = {
  version: 1,
  usesPlantProtectionProducts: true,
  appliesFertilizers: true,
};

/** Una campaña completa a la que no le falta nada de su parte. */
function campana(cambios: Record<string, unknown> = {}) {
  const base = {
    id: 'c1',
    managementMode: 'complete',
    notebookProfile: PERFIL_RESPONDIDO,
    cropUnits: [
      {
        id: 'u1',
        cropName: 'Aguacate',
        waterRegime: 'irrigated',
        productionSystem: 'conventional',
      },
    ],
    ...cambios,
  };
  return base as unknown as ReturnType<typeof presentarDetalle>;
}

function actividad(cambios: Record<string, unknown>): ActividadCompleta {
  return {
    id: 'a1',
    type: 'other',
    startDate: new Date('2026-05-10T00:00:00Z'),
    endDate: new Date('2026-05-10T00:00:00Z'),
    startTime: null,
    createdAt: new Date('2026-05-10T09:00:00Z'),
    phytosanitaryProducts: [],
    targets: [],
    irrigation: null,
    fertilization: null,
    phytosanitary: null,
    harvest: null,
    fieldWork: null,
    ...cambios,
  } as unknown as ActividadCompleta;
}

function revisar(entrada: Partial<EntradaDeCompletitud> = {}) {
  return calcularCompletitud({
    campana: campana(),
    finca: FINCA_COMPLETA,
    actividades: [],
    ...entrada,
  });
}

/** Los códigos de lo que falta, sin el sufijo del identificador. */
function codigos(resultado: ReturnType<typeof calcularCompletitud>): string[] {
  return [...resultado.campaign, ...resultado.activities.flatMap((f) => f.items)].map(
    (aviso) => aviso.code.split(':')[0],
  );
}

describe('Cuaderno completo', () => {
  describe('a quién se le revisa', () => {
    it('la campaña sencilla no se revisa: no prometió un cuaderno', () => {
      const resultado = revisar({ campana: campana({ managementMode: 'simple' }) });
      expect(resultado.applicable).toBe(false);
      expect(resultado.missingCount).toBe(0);
      expect(resultado.campaign).toEqual([]);
    });

    it('la revisión dice con qué reglas se hizo', () => {
      expect(revisar().rules).toEqual(CONJUNTO_DE_REGLAS);
      expect(CONJUNTO_DE_REGLAS.id).toMatch(/^ES-/);
    });

    it('cada aviso trae su fuente, para poder contrastarlo', () => {
      const todos = [
        ...revisar({ campana: campana({ notebookProfile: { version: 1 } }) }).campaign,
        ...revisar({
          actividades: [actividad({ type: 'phytosanitary' })],
        }).activities.flatMap((f) => f.items),
      ];
      expect(todos.length).toBeGreaterThan(0);
      for (const aviso of todos) {
        expect(aviso.sourceLabel.length).toBeGreaterThan(0);
        expect(aviso.why.length).toBeGreaterThan(0);
      }
    });

    it('nunca dice que la campaña cumple: solo qué falta', () => {
      const textos = JSON.stringify(revisar({ actividades: [actividad({ type: 'harvest' })] }));
      expect(textos).not.toMatch(/cumple/i);
    });
  });

  describe('la campaña y su finca', () => {
    it('sin responder el cuestionario, eso es lo primero que falta', () => {
      const resultado = revisar({ campana: campana({ notebookProfile: { version: 1 } }) });
      expect(codigos(resultado)).toContain('campaign.profile');
    });

    it('pide el titular y su NIF, y avisa si no se sabe la comunidad autónoma', () => {
      const resultado = revisar({
        finca: { holderName: null, holderNif: null, regionCode: null },
      });
      expect(codigos(resultado)).toEqual(
        expect.arrayContaining([
          'installation.holder_name',
          'installation.holder_nif',
          'installation.region',
        ]),
      );
      // La comunidad autónoma es cosa de la plataforma (reglas autonómicas),
      // no una exigencia: aviso, no información pendiente.
      const region = resultado.campaign.find((a) => a.code === 'installation.region');
      expect(region?.kind).toBe('warning');
      expect(region?.source).toBe('plataforma');
    });

    it('pide de cada unidad el régimen hídrico y el sistema de producción', () => {
      const resultado = revisar({
        campana: campana({ cropUnits: [{ id: 'u1', cropName: 'Olivo' }] }),
      });
      expect(codigos(resultado)).toEqual(
        expect.arrayContaining(['crop_unit.water_regime', 'crop_unit.production_system']),
      );
      expect(resultado.campaign.some((a) => a.label.includes('Olivo'))).toBe(true);
    });

    it('avisa si el cuestionario dice que no y hay actividades de ese tipo', () => {
      const resultado = revisar({
        campana: campana({
          notebookProfile: { version: 1, usesPlantProtectionProducts: false },
        }),
        actividades: [actividad({ type: 'phytosanitary' })],
      });
      expect(codigos(resultado)).toContain('campaign.profile_mismatch');
    });

    it('a una campaña completa y bien rellena no le falta nada', () => {
      expect(revisar().missingCount).toBe(0);
      expect(revisar().warningCount).toBe(0);
    });
  });

  describe('tratamientos fitosanitarios', () => {
    const tratamiento = (cambios: Record<string, unknown> = {}) =>
      actividad({
        type: 'phytosanitary',
        startTime: '08:30',
        phytosanitary: {
          problem: 'Mosca del olivo',
          bbchCode: '65',
          applicatorId: 'p1',
          equipmentId: 'e1',
        },
        phytosanitaryProducts: [
          {
            id: 'pr1',
            productName: 'Ejemplo',
            registryNumber: '25.123',
            dose: 1,
            doseUnit: 'l_ha',
          },
        ],
        ...cambios,
      });

    it('un tratamiento con todo no deja nada pendiente', () => {
      expect(revisar({ actividades: [tratamiento()] }).missingCount).toBe(0);
    });

    it('sin producto, sin hora, sin estado, sin aplicador ni equipo: todo eso falta', () => {
      const resultado = revisar({ actividades: [actividad({ type: 'phytosanitary' })] });
      expect(codigos(resultado)).toEqual(
        expect.arrayContaining([
          'phyto.product',
          'phyto.start_time',
          'phyto.stage',
          'phyto.applicator',
          'phyto.equipment',
          'phyto.problem',
        ]),
      );
    });

    it('cada producto pide su número de registro, y lo dice por su nombre', () => {
      const resultado = revisar({
        actividades: [
          tratamiento({
            phytosanitaryProducts: [
              { id: 'pr1', productName: 'Cobre 50', dose: 2, doseUnit: 'kg_ha' },
            ],
          }),
        ],
      });
      const aviso = resultado.activities[0].items.find((a) =>
        a.code.startsWith('phyto.registry_number'),
      );
      expect(aviso?.label).toContain('Cobre 50');
      expect(aviso?.source).toBe('ue_2023_564');
    });

    it('la dosis va por hectárea; por hectolitro vale si hay cantidad total', () => {
      const porHectolitro = (extra: Record<string, unknown>) =>
        codigos(
          revisar({
            actividades: [
              tratamiento({
                phytosanitaryProducts: [
                  {
                    id: 'pr1',
                    productName: 'Ejemplo',
                    registryNumber: '25.123',
                    dose: 0.2,
                    doseUnit: 'l_hl',
                    ...extra,
                  },
                ],
              }),
            ],
          }),
        );
      expect(porHectolitro({})).toContain('phyto.dose');
      expect(porHectolitro({ totalQuantity: 4 })).not.toContain('phyto.dose');
    });

    it('el aplicador guardado en la copia también cuenta: la persona pudo darse de baja', () => {
      const resultado = revisar({
        actividades: [
          tratamiento({
            phytosanitary: {
              problem: 'Mosca',
              bbchCode: '65',
              applicatorId: null,
              applicatorSnapshot: { displayName: 'Ana Ruiz' },
              equipmentId: 'e1',
            },
          }),
        ],
      });
      expect(codigos(resultado)).not.toContain('phyto.applicator');
    });
  });

  describe('abonados, riegos y cosechas', () => {
    it('del abonado pide material, dosis y método', () => {
      const resultado = revisar({ actividades: [actividad({ type: 'fertilization' })] });
      expect(codigos(resultado)).toEqual(
        expect.arrayContaining(['fert.material', 'fert.dose', 'fert.method']),
      );
    });

    it('sin riqueza avisa, pero como cálculo de la plataforma, no como norma', () => {
      const resultado = revisar({ actividades: [actividad({ type: 'fertilization' })] });
      const riqueza = resultado.activities[0].items.find((a) => a.code === 'fert.composition');
      expect(riqueza?.kind).toBe('warning');
      expect(riqueza?.source).toBe('plataforma');
    });

    it('avisa del abonado apuntado más de un mes después', () => {
      const tarde = actividad({
        type: 'fertilization',
        endDate: new Date('2026-05-10T00:00:00Z'),
        createdAt: new Date('2026-06-20T09:00:00Z'),
      });
      const aTiempo = actividad({
        type: 'fertilization',
        endDate: new Date('2026-05-10T00:00:00Z'),
        createdAt: new Date('2026-06-05T09:00:00Z'),
      });
      expect(codigos(revisar({ actividades: [tarde] }))).toContain('fert.delay');
      expect(codigos(revisar({ actividades: [aTiempo] }))).not.toContain('fert.delay');
    });

    it('del riego pide el agua aplicada y el sistema', () => {
      const resultado = revisar({ actividades: [actividad({ type: 'irrigation' })] });
      expect(codigos(resultado)).toEqual(
        expect.arrayContaining(['irrigation.amount', 'irrigation.system']),
      );
    });

    it('la cosecha sin cantidad es un aviso: sin ella no hay rendimiento', () => {
      const resultado = revisar({ actividades: [actividad({ type: 'harvest' })] });
      expect(resultado.missingCount).toBe(0);
      expect(codigos(resultado)).toContain('harvest.quantity');
    });

    it('las actividades sin nada pendiente no salen en la lista', () => {
      const resultado = revisar({
        actividades: [actividad({ type: 'observation' }), actividad({ type: 'sowing' })],
      });
      expect(resultado.activities).toEqual([]);
      expect(resultado.reviewedActivities).toBe(2);
    });
  });

  describe('catálogos de personas y equipos', () => {
    async function errores(dto: object) {
      const lista = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
      return lista.map((e) => e.property);
    }

    it('una persona necesita su tipo; el resto es opcional', async () => {
      const persona = plainToInstance(NotebookPersonCreateDto, { kind: 'own_staff' });
      await expect(errores(persona)).resolves.toEqual([]);
      const sinTipo = plainToInstance(NotebookPersonCreateDto, { firstName: 'Ana' });
      await expect(errores(sinTipo)).resolves.toEqual(['kind']);
      const inventado = plainToInstance(NotebookPersonCreateDto, { kind: 'vecino' });
      await expect(errores(inventado)).resolves.toEqual(['kind']);
    });

    it('la finca en blanco es "vale para todas", no un UUID mal formado', async () => {
      const comun = plainToInstance(NotebookPersonUpdateDto, { installationId: null });
      await expect(errores(comun)).resolves.toEqual([]);
      const mala = plainToInstance(NotebookPersonUpdateDto, { installationId: 'la de arriba' });
      await expect(errores(mala)).resolves.toEqual(['installationId']);
    });

    it('un equipo necesita su descripción y fechas de verdad', async () => {
      const equipo = plainToInstance(NotebookEquipmentCreateDto, { description: 'Atomizador' });
      await expect(errores(equipo)).resolves.toEqual([]);
      const sinNada = plainToInstance(NotebookEquipmentCreateDto, { description: '' });
      await expect(errores(sinNada)).resolves.toEqual(['description']);
      const fechaMala = plainToInstance(NotebookEquipmentCreateDto, {
        description: 'Atomizador',
        lastInspectionOn: '2026-02-30',
      });
      await expect(errores(fechaMala)).resolves.toEqual(['lastInspectionOn']);
    });

    it('en la lista se lee el nombre montado, o la empresa si no hay persona', () => {
      const persona = presentarPersona({
        id: 'p1',
        firstName: 'Ana',
        surname1: 'Ruiz',
        surname2: null,
        companyName: null,
        deletedAt: null,
      } as never);
      expect(persona.displayName).toBe('Ana Ruiz');

      const empresa = presentarPersona({
        id: 'p2',
        firstName: null,
        surname1: null,
        surname2: null,
        companyName: 'Tratamientos del Sur S.L.',
        deletedAt: null,
      } as never);
      expect(empresa.displayName).toBe('Tratamientos del Sur S.L.');

      const equipo = presentarEquipo({
        id: 'e1',
        description: 'Atomizador',
        brand: 'Hardi',
        model: null,
        acquiredOn: null,
        lastInspectionOn: null,
        deletedAt: null,
      } as never);
      expect(equipo.displayName).toBe('Atomizador · Hardi');
    });
  });

  describe('protección de la API', () => {
    it('los catálogos exigen la función contratada', () => {
      expect(Reflect.getMetadata(REQUIRE_FEATURE_KEY, NotebookController)).toEqual(['campaigns']);
    });

    it('elegirlos es leer; mantenerlos es configurar la explotación', () => {
      const permisoDe = (metodo: keyof NotebookController) =>
        Reflect.getMetadata(REQUIRE_PERMISSION_KEY, NotebookController.prototype[metodo]);

      expect(permisoDe('listPeople')).toBe('campaigns.read');
      expect(permisoDe('listEquipment')).toBe('campaigns.read');
      for (const metodo of [
        'createPerson',
        'updatePerson',
        'removePerson',
        'createEquipment',
        'updateEquipment',
        'removeEquipment',
      ] as const) {
        expect(permisoDe(metodo)).toBe('campaigns.update');
      }
    });

    it('la revisión del cuaderno se lee con el permiso de lectura', () => {
      expect(
        Reflect.getMetadata(REQUIRE_PERMISSION_KEY, ActivitiesController.prototype.completeness),
      ).toBe('campaigns.read');
    });
  });
});
