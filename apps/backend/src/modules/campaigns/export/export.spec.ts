import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { REQUIRE_FEATURE_KEY } from '../../../common/decorators/require-feature.decorator';
import { REQUIRE_PERMISSION_KEY } from '../../../common/decorators/require-permission.decorator';
import { CampaignsModule } from '../campaigns.module';
import { cifra, etiqueta, fecha, SISTEMAS_DE_RIEGO } from './etiquetas';
import { aCsv, aJson, nombreDelFichero } from './export-datos';
import { CuadernoExportado, VERSION_DEL_EXPORTADO } from './export-model';
import { aPdf } from './export-pdf';
import { CampaignExportController, ExportQueryDto } from './export.controller';

/**
 * El cuaderno exportado sin base de datos (fase 7 del #60). Lo que hay que
 * fijar: que los tres formatos salgan del mismo modelo, que el CSV se abra
 * bien en una hoja de cálculo en español y que ningún PDF diga que la campaña
 * "cumple".
 */

function cuaderno(cambios: Partial<CuadernoExportado> = {}): CuadernoExportado {
  return {
    schemaVersion: VERSION_DEL_EXPORTADO,
    generatedAt: '2026-09-23T08:00:00.000Z',
    source: 'live',
    organization: { name: 'Cooperativa del Sur' },
    installation: {
      name: 'Finca del Olivar',
      holderName: 'Ana Ruiz',
      holderNif: '12345678Z',
      reaCode: null,
      address: 'Camino de la Fuente, s/n',
      regionCode: 'ES-AN',
    },
    campaign: {
      id: 'c1',
      name: 'Olivo · 2026',
      status: 'active',
      managementMode: 'complete',
      startDate: '2026-03-01',
      expectedEndDate: '2026-12-15',
      endDate: null,
      areaHa: 3.5,
      notes: null,
      declaredProductionKg: null,
      closingNotes: null,
      notebookProfile: { version: 1, usesPlantProtectionProducts: true },
    },
    cropUnits: [
      {
        id: 'u1',
        cropName: 'Olivo',
        variety: 'Picual',
        previousCrop: null,
        waterRegime: 'rainfed',
        growingEnvironment: 'open_field',
        productionSystem: 'conventional',
        areaHa: 3.5,
        expectedYieldKgHa: null,
        parcels: [{ name: 'Olivar Bajo', areaHa: 3.5 }],
      },
    ],
    activities: [
      {
        id: 'a1',
        type: 'phytosanitary',
        startDate: '2026-05-10',
        endDate: '2026-05-10',
        startTime: '08:30',
        notes: null,
        areaHa: 3.5,
        targets: [{ parcelName: 'Olivar Bajo', cropName: 'Olivo Picual', areaHa: 3.5 }],
        irrigation: null,
        fertilization: null,
        phytosanitary: {
          problem: 'Repilo',
          phenologicalStageLabel: 'Floración',
          bbchCode: '65',
          products: [
            { productName: 'Cobre 50', registryNumber: '25.123', dose: 2, doseUnit: 'kg_ha' },
            { productName: 'Mojante', registryNumber: null, dose: 0.2, doseUnit: 'l_hl' },
          ],
        },
        harvest: null,
        fieldWork: null,
      },
      {
        id: 'a2',
        type: 'irrigation',
        startDate: '2026-06-01',
        endDate: '2026-06-15',
        startTime: null,
        notes: 'Quincena con "calor"',
        areaHa: 3.5,
        targets: [{ parcelName: 'Olivar Bajo', cropName: 'Olivo Picual', areaHa: 3.5 }],
        irrigation: { amount: 18, amountUnit: 'm3_ha', volumeM3: 63, system: 'drip' },
        fertilization: null,
        phytosanitary: null,
        harvest: null,
        fieldWork: null,
      },
    ],
    summary: {
      campaignId: 'c1',
      areaHa: 3.5,
      activityCount: 2,
      lastActivity: { type: 'irrigation', date: '2026-06-01' },
      irrigation: { count: 1, volumeM3: 63, volumeM3PerHa: 18, withoutVolume: 0 },
      fertilization: null,
      phytosanitary: { count: 1, distinctProducts: 2 },
      harvest: null,
      fieldWork: null,
      observations: null,
      cropUnits: [],
    } as unknown as CuadernoExportado['summary'],
    pending: null,
    ...cambios,
  };
}

describe('Cuaderno exportado', () => {
  describe('etiquetas y cifras', () => {
    it('traduce lo que la base guarda en inglés, y deja pasar lo que no conoce', () => {
      expect(etiqueta(SISTEMAS_DE_RIEGO, 'drip')).toBe('Goteo');
      expect(etiqueta(SISTEMAS_DE_RIEGO, 'lo_que_venga')).toBe('lo_que_venga');
      expect(etiqueta(SISTEMAS_DE_RIEGO, null)).toBe('');
    });

    it('las cifras van con coma decimal y las fechas como se leen aquí', () => {
      expect(cifra(15.25)).toBe('15,25');
      expect(cifra(1200)).toBe('1200');
      expect(cifra(null)).toBe('');
      expect(fecha('2026-05-10')).toBe('10/05/2026');
      expect(fecha(null)).toBe('');
    });
  });

  describe('JSON', () => {
    it('lleva su versión de formato y el cuaderno entero', () => {
      const json = JSON.parse(aJson(cuaderno()).toString('utf8'));

      expect(json.schemaVersion).toBe(VERSION_DEL_EXPORTADO);
      expect(json.campaign.name).toBe('Olivo · 2026');
      expect(json.activities).toHaveLength(2);
      expect(json.installation.holderNif).toBe('12345678Z');
    });

    it('dice de dónde salen los datos: de lo vivo o de la instantánea', () => {
      expect(JSON.parse(aJson(cuaderno()).toString('utf8')).source).toBe('live');
      expect(JSON.parse(aJson(cuaderno({ source: 'snapshot' })).toString('utf8')).source).toBe(
        'snapshot',
      );
    });
  });

  describe('CSV', () => {
    const texto = () => aCsv(cuaderno()).toString('utf8');

    it('se abre bien en una hoja de cálculo en español', () => {
      const csv = texto();
      // BOM + punto y coma: sin eso, Excel en español lo abre en una columna
      // y con los acentos rotos.
      expect(csv.startsWith('﻿')).toBe(true);
      expect(csv.split('\r\n')[0]).toContain('fecha_inicio;fecha_fin');
      expect(csv).toContain('18,0'.replace('18,0', '18')); // coma decimal, no punto
      expect(csv).not.toContain('63.0');
    });

    it('un tratamiento da una fila por producto', () => {
      const filas = texto().split('\r\n').slice(1);
      const deTratamiento = filas.filter((f) => f.includes('Tratamiento fitosanitario'));

      expect(deTratamiento).toHaveLength(2);
      expect(deTratamiento[0]).toContain('Cobre 50');
      expect(deTratamiento[0]).toContain('25.123');
      expect(deTratamiento[1]).toContain('Mojante');
    });

    it('las comillas y los puntos y coma del texto no rompen las columnas', () => {
      const filaDeRiego = texto()
        .split('\r\n')
        .find((f) => f.includes('Riego'))!;
      expect(filaDeRiego).toContain('"Quincena con ""calor"""');
    });

    it('lo lee una persona: nada de códigos en inglés ni unidades crudas', () => {
      // La primera versión sacaba "fertilizer_product · broadcast" y "kg_ha"
      // en una hoja que se abre en Excel para leerla.
      const csv = aCsv(
        cuaderno({
          activities: [
            {
              ...cuaderno().activities[1],
              type: 'fertilization',
              irrigation: null,
              fertilization: {
                materialType: 'fertilizer_product',
                applicationMethod: 'broadcast',
                dose: 350,
                doseUnit: 'kg_ha',
              },
            },
          ],
        }),
      ).toString('utf8');

      expect(csv).toContain('Producto fertilizante · A voleo');
      expect(csv).toContain('kg/ha');
      expect(csv).not.toContain('fertilizer_product');
      expect(csv).not.toContain('kg_ha');
    });

    it('lo que no aplica se queda vacío, nunca a cero', () => {
      const filaDeRiego = texto()
        .split('\r\n')
        .find((f) => f.includes('Riego'))!
        .split(';');
      // `producto` y `numero_registro` no aplican a un riego.
      expect(filaDeRiego[7]).toBe('');
      expect(filaDeRiego[8]).toBe('');
    });
  });

  describe('PDF', () => {
    it('sale un PDF de verdad en las dos disposiciones', async () => {
      const informe = await aPdf(cuaderno(), 'informe');
      const cue = await aPdf(cuaderno(), 'cue');

      expect(informe.subarray(0, 5).toString('latin1')).toBe('%PDF-');
      expect(cue.subarray(0, 5).toString('latin1')).toBe('%PDF-');
      expect(informe.byteLength).toBeGreaterThan(2000);
      expect(cue.byteLength).toBeGreaterThan(2000);
    });

    it('un cuaderno sin nada registrado tampoco revienta', async () => {
      const vacio = cuaderno({
        activities: [],
        cropUnits: [],
        summary: {
          campaignId: 'c1',
          areaHa: 0,
          activityCount: 0,
          lastActivity: null,
          irrigation: null,
          fertilization: null,
          phytosanitary: null,
          harvest: null,
          fieldWork: null,
          observations: null,
          cropUnits: [],
        } as unknown as CuadernoExportado['summary'],
      });
      await expect(aPdf(vacio, 'informe')).resolves.toBeInstanceOf(Buffer);
      await expect(aPdf(vacio, 'cue')).resolves.toBeInstanceOf(Buffer);
    });

    it('el nombre del fichero sale del nombre de la campaña, sin caracteres prohibidos', () => {
      expect(nombreDelFichero(cuaderno(), 'pdf')).toBe('Cuaderno - Olivo · 2026.pdf');
      const raro = cuaderno({
        campaign: { ...cuaderno().campaign, name: 'Olivo/2026: "el bueno"' },
      });
      expect(nombreDelFichero(raro, 'csv')).toBe('Cuaderno - Olivo2026 el bueno.csv');
    });
  });

  describe('protección de la API', () => {
    it('exige la función contratada y el permiso de lectura', () => {
      expect(Reflect.getMetadata(REQUIRE_FEATURE_KEY, CampaignExportController)).toEqual([
        'campaigns',
      ]);
      expect(
        Reflect.getMetadata(REQUIRE_PERMISSION_KEY, CampaignExportController.prototype.export),
      ).toBe('campaigns.read');
    });

    it('la ruta está dada de alta en el módulo', () => {
      // Sin esto la exportación existiría en el código y no en la API: el
      // servicio se puede probar igual, y el fallo solo se vería al usarla.
      const controladores = Reflect.getMetadata('controllers', CampaignsModule) as unknown[];
      expect(controladores).toContain(CampaignExportController);
    });

    it('solo admite los formatos y disposiciones que existen', async () => {
      const errores = async (valores: object) => {
        const lista = await validate(plainToInstance(ExportQueryDto, valores), {
          whitelist: true,
          forbidNonWhitelisted: true,
        });
        return lista.map((e) => e.property);
      };

      await expect(errores({})).resolves.toEqual([]);
      await expect(errores({ format: 'pdf', layout: 'cue' })).resolves.toEqual([]);
      await expect(errores({ format: 'xlsx' })).resolves.toEqual(['format']);
      await expect(errores({ layout: 'bonito' })).resolves.toEqual(['layout']);
    });
  });
});
