import { CreateBucketCommand, S3Client } from '@aws-sdk/client-s3';
import { ConfigService } from '@nestjs/config';
import { StorageService } from '../../src/common/storage/storage.service';
import { claveObjetoSatelite } from '../../src/common/storage/object-keys';

/**
 * `StorageService` contra un S3 de verdad — el MinIO de `docker-compose.yml`,
 * que es el mismo protocolo que el Hetzner Object Storage de staging. Las
 * pruebas unitarias mockean el SDK, así que no ven lo único que puede fallar
 * aquí: firma, estilo de ruta y que la URL firmada sirva de verdad para
 * descargar.
 *
 * Se salta si el entorno no tiene S3 configurado (el CI de hoy no levanta
 * MinIO): más vale una prueba que corre en local y en staging que un CI
 * frágil. Para correrla:
 *
 *   S3_ENDPOINT=http://localhost:19000 S3_BUCKET=iot-platform-test \
 *   S3_ACCESS_KEY=dev_access_key S3_SECRET_KEY=dev_secret_key \
 *   npx jest test/integration/storage.spec.ts
 */
const hayS3 = Boolean(process.env.S3_ENDPOINT && process.env.S3_BUCKET);
const describeSiHayS3 = hayS3 ? describe : describe.skip;

describeSiHayS3('StorageService contra un S3 real (MinIO)', () => {
  let storage: StorageService;
  const claves: string[] = [];

  const config = {
    get: (clave: string, porDefecto?: string) => process.env[clave] ?? porDefecto,
    getOrThrow: (clave: string) => {
      const valor = process.env[clave];
      if (!valor) throw new Error(`Falta ${clave}`);
      return valor;
    },
  } as unknown as ConfigService;

  beforeAll(async () => {
    // El bucket de pruebas se crea aquí: así la prueba no depende de que
    // alguien lo haya creado a mano en su MinIO.
    const cliente = new S3Client({
      endpoint: process.env.S3_ENDPOINT,
      region: process.env.S3_REGION ?? 'us-east-1',
      credentials: {
        accessKeyId: process.env.S3_ACCESS_KEY as string,
        secretAccessKey: process.env.S3_SECRET_KEY as string,
      },
      forcePathStyle: true,
    });
    try {
      await cliente.send(new CreateBucketCommand({ Bucket: process.env.S3_BUCKET as string }));
    } catch (error) {
      const nombre = (error as { name?: string }).name;
      if (nombre !== 'BucketAlreadyOwnedByYou' && nombre !== 'BucketAlreadyExists') {
        throw error;
      }
    }
    storage = new StorageService(config);
  });

  afterAll(async () => {
    if (storage) {
      await storage.borrar(claves);
    }
  });

  it('sube un objeto, lo encuentra y lo devuelve por una URL firmada', async () => {
    const clave = claveObjetoSatelite({
      organizationId: 'org-de-prueba',
      parcelId: `parcela-${Date.now()}`,
      provider: 'copernicus',
      collection: 'sentinel-2-l2a',
      acquisitionTime: new Date('2026-09-15T10:42:00Z'),
      observationId: 'obs-de-prueba',
      processingVersion: 'ndvi-s2-v1',
      tipo: 'ndvi_raster',
    });
    claves.push(clave);
    const contenido = new TextEncoder().encode('contenido de prueba del ráster');

    const subido = await storage.subir({
      clave,
      cuerpo: contenido,
      contentType: 'image/tiff',
      metadatos: { processingversion: 'ndvi-s2-v1' },
    });

    expect(subido.byteSize).toBe(contenido.byteLength);
    await expect(storage.existe(clave)).resolves.toBe(true);

    // Lo que de verdad importa: que el enlace firmado sirva sin credenciales.
    const enlace = await storage.urlFirmada(clave, 120);
    const respuesta = await fetch(enlace.url);
    expect(respuesta.status).toBe(200);
    expect(new Uint8Array(await respuesta.arrayBuffer())).toEqual(contenido);
  });

  it('sin firmar, el objeto no se descarga: el bucket no es público', async () => {
    const clave = claves[0];
    const sinFirmar = `${process.env.S3_ENDPOINT}/${process.env.S3_BUCKET}/${clave}`;

    const respuesta = await fetch(sinFirmar);
    expect(respuesta.status).toBeGreaterThanOrEqual(400);
  });

  it('borrar deja de encontrarlo', async () => {
    const clave = `satellite/org-de-prueba/borrame-${Date.now()}.tif`;
    await storage.subir({
      clave,
      cuerpo: new TextEncoder().encode('efímero'),
      contentType: 'image/tiff',
    });
    await expect(storage.existe(clave)).resolves.toBe(true);

    await storage.borrar([clave]);
    await expect(storage.existe(clave)).resolves.toBe(false);
  });
});

// Jest se queja si un fichero de prueba no declara ninguna: cuando no hay S3
// configurado, el describe entero se salta y hace falta algo que contar.
if (!hayS3) {
  it('se salta: no hay S3 configurado en este entorno', () => {
    expect(hayS3).toBe(false);
  });
}
