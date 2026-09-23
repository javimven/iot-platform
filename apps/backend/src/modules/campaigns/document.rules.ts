import { BadRequestException } from '@nestjs/common';

/**
 * Qué se admite como documento del cuaderno (fase 6 del #60) y cómo se
 * reconoce.
 *
 * **El tipo lo decide el contenido, no lo que diga el cliente.** El
 * `Content-Type` de una subida lo pone quien sube: un `.exe` anunciado como
 * `image/jpeg` entraría igual. Aquí se miran los primeros bytes, que son los
 * que de verdad dicen qué es el fichero, y se guarda lo detectado.
 */

/** Tamaño máximo de un documento. Una foto de móvil ronda los 3-5 MB. */
export const MAXIMO_BYTES_DOCUMENTO = 15 * 1024 * 1024;

/** Tipos del CHECK `documents_tipo` de la migración 0012. */
export const TIPOS_DE_DOCUMENTO = [
  'photo',
  'invoice',
  'contract',
  'inspection_certificate',
  'container_management',
  'analysis',
  'advice',
  'delivery_note',
  'fertilization_plan',
  'other',
] as const;

export type TipoDeDocumento = (typeof TIPOS_DE_DOCUMENTO)[number];

interface Formato {
  mediaType: string;
  extension: string;
  /** Devuelve true si el contenido es de este formato. */
  reconoce: (bytes: Buffer) => boolean;
}

function empiezaPor(bytes: Buffer, firma: number[]): boolean {
  return bytes.length >= firma.length && firma.every((byte, i) => bytes[i] === byte);
}

/** La caja `ftyp` de un HEIC/HEIF va en los bytes 4-8, con su marca detrás. */
function esHeic(bytes: Buffer): boolean {
  if (bytes.length < 12 || bytes.toString('latin1', 4, 8) !== 'ftyp') {
    return false;
  }
  const marca = bytes.toString('latin1', 8, 12);
  return ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(marca);
}

const FORMATOS: Formato[] = [
  {
    mediaType: 'image/jpeg',
    extension: 'jpg',
    reconoce: (b) => empiezaPor(b, [0xff, 0xd8, 0xff]),
  },
  {
    mediaType: 'image/png',
    extension: 'png',
    reconoce: (b) => empiezaPor(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  },
  {
    mediaType: 'image/webp',
    extension: 'webp',
    reconoce: (b) =>
      b.length >= 12 &&
      b.toString('latin1', 0, 4) === 'RIFF' &&
      b.toString('latin1', 8, 12) === 'WEBP',
  },
  {
    // Lo que manda un iPhone sin conversión. Se guarda tal cual: convertirlo
    // en el servidor sería reprocesar la prueba de lo que se hizo.
    mediaType: 'image/heic',
    extension: 'heic',
    reconoce: esHeic,
  },
  {
    mediaType: 'application/pdf',
    extension: 'pdf',
    reconoce: (b) => b.toString('latin1', 0, 5) === '%PDF-',
  },
];

export interface FormatoDetectado {
  mediaType: string;
  extension: string;
}

/** El formato real del contenido, o `null` si no es ninguno de los admitidos. */
export function detectarFormato(bytes: Buffer): FormatoDetectado | null {
  const formato = FORMATOS.find((f) => f.reconoce(bytes));
  return formato ? { mediaType: formato.mediaType, extension: formato.extension } : null;
}

/** Lo que se le dice a quien sube algo que no vale, en español y concreto. */
export function comprobarArchivo(bytes: Buffer | undefined): FormatoDetectado {
  if (!bytes || bytes.byteLength === 0) {
    throw new BadRequestException('No llegó ningún archivo.');
  }
  if (bytes.byteLength > MAXIMO_BYTES_DOCUMENTO) {
    const megas = Math.round(MAXIMO_BYTES_DOCUMENTO / (1024 * 1024));
    throw new BadRequestException(`El archivo pasa de ${megas} MB.`);
  }
  const formato = detectarFormato(bytes);
  if (!formato) {
    throw new BadRequestException(
      'Solo se admiten fotos (JPG, PNG, WEBP o HEIC) y documentos PDF.',
    );
  }
  return formato;
}

/** El nombre del fichero, sin rutas ni sorpresas, para guardarlo en la base. */
export function nombreLimpio(nombre: string | undefined, extension: string): string {
  const soloNombre = (nombre ?? '').split(/[\\/]/).pop()?.trim() ?? '';
  if (soloNombre.length === 0) {
    return `documento.${extension}`;
  }
  return soloNombre.slice(0, 200);
}
