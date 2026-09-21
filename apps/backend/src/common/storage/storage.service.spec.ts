import { ConfigService } from '@nestjs/config';
import { StorageService } from './storage.service';
import { claveObjetoSatelite, prefijoParcela } from './object-keys';

const enviado: Array<{ constructor: string; input: Record<string, unknown> }> = [];
let respuestaSend: (comando: { constructor: { name: string } }) => unknown = () => ({});

jest.mock('@aws-sdk/client-s3', () => {
  class ComandoFalso {
    constructor(public input: Record<string, unknown>) {}
  }
  return {
    S3Client: class {
      constructor(public config: Record<string, unknown>) {}
      send(comando: { constructor: { name: string }; input: Record<string, unknown> }) {
        enviado.push({ constructor: comando.constructor.name, input: comando.input });
        return Promise.resolve(respuestaSend(comando));
      }
    },
    PutObjectCommand: class extends ComandoFalso {},
    GetObjectCommand: class extends ComandoFalso {},
    HeadObjectCommand: class extends ComandoFalso {},
    DeleteObjectsCommand: class extends ComandoFalso {},
  };
});

jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn().mockResolvedValue('https://bucket.example/ndvi.tif?X-Amz-Signature=xxx'),
}));

/**
 * El bucket existía desde el primer despliegue pero ninguna línea de código lo
 * usaba (BACKLOG.md #36). Estas pruebas fijan lo que no debe cambiarse sin
 * pensarlo: nada sale sin firmar, nada se escribe en disco, y las claves son
 * deterministas para poder reprocesar.
 */
describe('StorageService', () => {
  function build(env: Record<string, string> = {}) {
    const valores: Record<string, string> = {
      S3_ENDPOINT: 'http://localhost:19000',
      S3_BUCKET: 'iot-platform-dev',
      S3_ACCESS_KEY: 'dev_access_key',
      S3_SECRET_KEY: 'dev_secret_key',
      ...env,
    };
    const config = {
      get: jest.fn((clave: string, porDefecto?: string) => valores[clave] ?? porDefecto),
      getOrThrow: jest.fn((clave: string) => {
        if (!valores[clave]) throw new Error(`Falta ${clave}`);
        return valores[clave];
      }),
    } as unknown as ConfigService;
    return new StorageService(config);
  }

  beforeEach(() => {
    enviado.length = 0;
    respuestaSend = () => ({});
  });

  it('sube el objeto con su tipo y devuelve tamaño y checksum', async () => {
    const service = build();
    const cuerpo = new TextEncoder().encode('no es un tiff, pero sirve');

    const resultado = await service.subir({
      clave: 'satellite/org/parcela/ndvi.tif',
      cuerpo,
      contentType: 'image/tiff',
      metadatos: { processingVersion: 'ndvi-s2-v1' },
    });

    expect(resultado.byteSize).toBe(cuerpo.byteLength);
    expect(resultado.checksum).toHaveLength(64); // sha256 en hexadecimal
    expect(enviado[0].constructor).toBe('PutObjectCommand');
    expect(enviado[0].input).toEqual(
      expect.objectContaining({
        Bucket: 'iot-platform-dev',
        Key: 'satellite/org/parcela/ndvi.tif',
        ContentType: 'image/tiff',
        ContentLength: cuerpo.byteLength,
      }),
    );
  });

  it('el mismo contenido da el mismo checksum, y otro distinto', async () => {
    const service = build();
    const uno = await service.subir({
      clave: 'a',
      cuerpo: new TextEncoder().encode('mismo'),
      contentType: 'image/tiff',
    });
    const dos = await service.subir({
      clave: 'b',
      cuerpo: new TextEncoder().encode('mismo'),
      contentType: 'image/tiff',
    });
    const tres = await service.subir({
      clave: 'c',
      cuerpo: new TextEncoder().encode('otro'),
      contentType: 'image/tiff',
    });

    expect(uno.checksum).toBe(dos.checksum);
    expect(uno.checksum).not.toBe(tres.checksum);
  });

  it('rechaza un objeto vacío y uno desmesurado antes de salir a la red', async () => {
    const service = build();

    await expect(
      service.subir({ clave: 'x', cuerpo: new Uint8Array(0), contentType: 'image/tiff' }),
    ).rejects.toThrow(/vacío/);
    await expect(
      service.subir({
        clave: 'x',
        cuerpo: new Uint8Array(65 * 1024 * 1024),
        contentType: 'image/tiff',
      }),
    ).rejects.toThrow(/demasiado grande/);
    expect(enviado).toHaveLength(0);
  });

  it('devuelve una URL firmada con su caducidad', async () => {
    const service = build();
    const antes = Date.now();

    const enlace = await service.urlFirmada('satellite/org/parcela/ndvi.png', 600);

    expect(enlace.url).toContain('X-Amz-Signature');
    expect(enlace.expiresAt.getTime()).toBeGreaterThanOrEqual(antes + 600 * 1000);
  });

  it('existe() distingue "no está" de un fallo de verdad', async () => {
    const service = build();

    respuestaSend = () => {
      const error = new Error('Not Found');
      error.name = 'NotFound';
      throw error;
    };
    await expect(service.existe('lo-que-sea')).resolves.toBe(false);

    respuestaSend = () => {
      const error = new Error('Access Denied');
      error.name = 'AccessDenied';
      throw error;
    };
    await expect(service.existe('lo-que-sea')).rejects.toThrow('Access Denied');
  });

  it('borrar sin claves no llama a S3', async () => {
    const service = build();
    await service.borrar([]);
    expect(enviado).toHaveLength(0);
  });

  it('no monta el cliente al construir el servicio: varios entornos no tienen S3', () => {
    const service = build({ S3_ENDPOINT: '', S3_BUCKET: '' });
    expect(service.estaConfigurado()).toBe(false); // y no ha lanzado nada
  });

  describe('claves de objeto', () => {
    const base = {
      organizationId: 'org-1',
      parcelId: 'parcela-1',
      provider: 'copernicus',
      collection: 'sentinel-2-l2a',
      acquisitionTime: new Date('2026-09-15T10:42:00Z'),
      observationId: 'obs-1',
      processingVersion: 'ndvi-s2-v1',
    };

    it('es determinista y ordena por organización, parcela, proveedor y fecha', () => {
      expect(claveObjetoSatelite({ ...base, tipo: 'ndvi_raster' })).toBe(
        'satellite/org-1/parcela-1/copernicus/sentinel-2-l2a/2026/09/obs-1/ndvi-s2-v1/ndvi.tif',
      );
      expect(claveObjetoSatelite({ ...base, tipo: 'ndvi_preview' })).toBe(
        'satellite/org-1/parcela-1/copernicus/sentinel-2-l2a/2026/09/obs-1/ndvi-s2-v1/ndvi.png',
      );
    });

    it('usa el mes en UTC, no el local: una pasada a las 23:30 del día 30 no cae en otro mes', () => {
      const finDeMes = new Date('2026-09-30T23:30:00Z');
      expect(
        claveObjetoSatelite({ ...base, acquisitionTime: finDeMes, tipo: 'ndvi_raster' }),
      ).toContain('/2026/09/');
    });

    it('cambiar la versión de procesado no pisa lo anterior', () => {
      const v1 = claveObjetoSatelite({ ...base, tipo: 'ndvi_raster' });
      const v2 = claveObjetoSatelite({
        ...base,
        processingVersion: 'ndvi-s2-v2',
        tipo: 'ndvi_raster',
      });
      expect(v1).not.toBe(v2);
    });

    it('el prefijo de una parcela cuelga de su organización', () => {
      expect(prefijoParcela('org-1', 'parcela-1')).toBe('satellite/org-1/parcela-1/');
    });
  });
});
