import { createHash } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

/**
 * Tope de lo que se sube de una vez. Un NDVI de Sentinel-2 a 10 m de una
 * parcela de 50 ha son un par de megas; 64 MB solo se alcanzan si algo ha ido
 * mal (una parcela dibujada del tamaño de una provincia, por ejemplo), y el
 * objeto se arma en memoria, así que conviene que reviente aquí con un
 * mensaje claro y no por falta de RAM en la VPS.
 */
const MAXIMO_BYTES = 64 * 1024 * 1024;

/** Vida por defecto de un enlace firmado: lo justo para abrir una imagen. */
const SEGUNDOS_FIRMA_POR_DEFECTO = 15 * 60;

export interface ObjetoSubido {
  objectKey: string;
  byteSize: number;
  /** SHA-256 en hexadecimal: sirve para saber si dos procesados dieron lo mismo. */
  checksum: string;
}

export interface EnlaceFirmado {
  url: string;
  expiresAt: Date;
}

/**
 * Almacenamiento de objetos compatible con S3 (DEPLOYMENT.md §1/§7). En
 * staging y producción es Hetzner Object Storage, ya aprovisionado por
 * Terraform (`infra/terraform/modules/object_storage`); en local, el MinIO de
 * `docker-compose.yml`. El mismo código vale para los dos: la única
 * diferencia es el endpoint.
 *
 * Nace con el módulo de satélite (BACKLOG.md #36): el bucket existía desde el
 * primer despliegue pero ninguna línea de código lo usaba.
 *
 * Dos decisiones que conviene no deshacer:
 *
 * - **El cliente se crea la primera vez que se usa**, no al arrancar. La
 *   mayoría de los procesos (`api`, `ingestion`) no tocan S3, y varios
 *   entornos no tienen las credenciales puestas: fallar en el arranque por
 *   una función que esa instancia no usa sería un mal negocio.
 * - **El bucket es privado y nada sale de aquí sin firmar**. El cliente nunca
 *   ve las credenciales (SECURITY.md); lo que recibe es una URL con caducidad.
 */
@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private cliente?: S3Client;
  private bucketCache?: string;

  constructor(private readonly config: ConfigService) {}

  /**
   * Sube un objeto. El cuerpo llega ya en memoria a propósito: **nada se
   * escribe en el disco de la VPS**, que tiene poco sitio y ya se llenó una
   * vez dejando la plataforma tres días sin ingerir datos (BACKLOG.md #54).
   */
  async subir(objeto: {
    clave: string;
    cuerpo: Uint8Array;
    contentType: string;
    metadatos?: Record<string, string>;
  }): Promise<ObjetoSubido> {
    if (objeto.cuerpo.byteLength === 0) {
      throw new Error(`Objeto vacío, no se sube: ${objeto.clave}`);
    }
    if (objeto.cuerpo.byteLength > MAXIMO_BYTES) {
      throw new Error(
        `Objeto demasiado grande (${objeto.cuerpo.byteLength} bytes, máximo ${MAXIMO_BYTES}): ${objeto.clave}`,
      );
    }

    const checksum = createHash('sha256').update(objeto.cuerpo).digest('hex');
    const comienzo = Date.now();

    await this.s3().send(
      new PutObjectCommand({
        Bucket: this.bucket(),
        Key: objeto.clave,
        Body: objeto.cuerpo,
        ContentType: objeto.contentType,
        ContentLength: objeto.cuerpo.byteLength,
        Metadata: objeto.metadatos,
      }),
    );

    this.logger.log(
      `Subido ${objeto.clave} (${objeto.cuerpo.byteLength} bytes, ${Date.now() - comienzo} ms)`,
    );
    return { objectKey: objeto.clave, byteSize: objeto.cuerpo.byteLength, checksum };
  }

  /**
   * Enlace temporal de descarga para el cliente. Nunca se registra la URL
   * entera en el log: lleva la firma, que es una credencial de usar y tirar.
   */
  async urlFirmada(clave: string, segundos = SEGUNDOS_FIRMA_POR_DEFECTO): Promise<EnlaceFirmado> {
    const url = await getSignedUrl(
      this.s3(),
      new GetObjectCommand({ Bucket: this.bucket(), Key: clave }),
      { expiresIn: segundos },
    );
    return { url, expiresAt: new Date(Date.now() + segundos * 1000) };
  }

  /** `true` si el objeto está donde dice la base de datos. */
  async existe(clave: string): Promise<boolean> {
    try {
      await this.s3().send(new HeadObjectCommand({ Bucket: this.bucket(), Key: clave }));
      return true;
    } catch (error) {
      const nombre = (error as { name?: string }).name;
      if (nombre === 'NotFound' || nombre === 'NoSuchKey') {
        return false;
      }
      throw error;
    }
  }

  /**
   * Borra objetos. Se usa al limpiar lo que quedó a medias: si la subida fue
   * bien pero la fila de la base no llegó a escribirse, el objeto queda
   * huérfano y nadie sabría de él.
   */
  async borrar(claves: string[]): Promise<void> {
    if (claves.length === 0) {
      return;
    }
    await this.s3().send(
      new DeleteObjectsCommand({
        Bucket: this.bucket(),
        Delete: { Objects: claves.map((Key) => ({ Key })), Quiet: true },
      }),
    );
  }

  /** Si hay almacenamiento configurado en este entorno. */
  estaConfigurado(): boolean {
    return Boolean(this.config.get<string>('S3_ENDPOINT') && this.config.get<string>('S3_BUCKET'));
  }

  private bucket(): string {
    this.bucketCache ??= this.config.getOrThrow<string>('S3_BUCKET');
    return this.bucketCache;
  }

  private s3(): S3Client {
    if (this.cliente) {
      return this.cliente;
    }
    const endpoint = this.config.getOrThrow<string>('S3_ENDPOINT');
    this.cliente = new S3Client({
      endpoint,
      // Hetzner Object Storage nombra su región como la del servidor (`fsn1`);
      // MinIO se la traga cualquiera. El SDK exige una, así que hay un valor
      // por defecto en vez de obligar a ponerla en desarrollo.
      region: this.config.get<string>('S3_REGION', 'us-east-1'),
      credentials: {
        accessKeyId: this.config.getOrThrow<string>('S3_ACCESS_KEY'),
        secretAccessKey: this.config.getOrThrow<string>('S3_SECRET_KEY'),
      },
      // Estilo de ruta (`endpoint/bucket/clave`) y no de subdominio: con un
      // endpoint propio, el estilo virtual exige que el DNS resuelva
      // `bucket.endpoint`, que es justo lo que MinIO en local no hace.
      forcePathStyle: true,
    });
    this.logger.log(`Almacenamiento de objetos listo (${endpoint})`); // nunca las claves
    return this.cliente;
  }
}
