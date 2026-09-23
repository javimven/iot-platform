import { BadRequestException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { REQUIRE_FEATURE_KEY } from '../../common/decorators/require-feature.decorator';
import { REQUIRE_PERMISSION_KEY } from '../../common/decorators/require-permission.decorator';
import { claveDocumento } from '../../common/storage/object-keys';
import {
  comprobarArchivo,
  detectarFormato,
  MAXIMO_BYTES_DOCUMENTO,
  nombreLimpio,
} from './document.rules';
import { DocumentsController } from './documents.controller';
import { DocumentUploadDto } from './dto/document.dto';

/** Cabeceras reales de cada formato, que es lo único que se mira. */
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
const PDF = Buffer.from('%PDF-1.7\n%âãÏÓ', 'latin1');
const WEBP = Buffer.concat([
  Buffer.from('RIFF', 'latin1'),
  Buffer.from([0x10, 0x00, 0x00, 0x00]),
  Buffer.from('WEBPVP8 ', 'latin1'),
]);
const HEIC = Buffer.concat([
  Buffer.from([0x00, 0x00, 0x00, 0x18]),
  Buffer.from('ftypheic', 'latin1'),
]);

describe('Documentos del cuaderno', () => {
  describe('qué se admite', () => {
    it('reconoce cada formato por su contenido, no por lo que diga el cliente', () => {
      expect(detectarFormato(JPEG)).toEqual({ mediaType: 'image/jpeg', extension: 'jpg' });
      expect(detectarFormato(PNG)).toEqual({ mediaType: 'image/png', extension: 'png' });
      expect(detectarFormato(WEBP)).toEqual({ mediaType: 'image/webp', extension: 'webp' });
      expect(detectarFormato(HEIC)).toEqual({ mediaType: 'image/heic', extension: 'heic' });
      expect(detectarFormato(PDF)).toEqual({ mediaType: 'application/pdf', extension: 'pdf' });
    });

    it('un ejecutable disfrazado de foto no entra', () => {
      // `MZ` es la cabecera de un .exe de Windows. Con el `Content-Type` del
      // cliente habría pasado por una imagen.
      const ejecutable = Buffer.from('MZ\u0090\u0000\u0003', 'latin1');
      expect(detectarFormato(ejecutable)).toBeNull();
      expect(() => comprobarArchivo(ejecutable)).toThrow(BadRequestException);
      expect(() => comprobarArchivo(ejecutable)).toThrow(/Solo se admiten fotos/);
    });

    it('un archivo vacío o que no llega se dice en español', () => {
      expect(() => comprobarArchivo(undefined)).toThrow(/No llegó ningún archivo/);
      expect(() => comprobarArchivo(Buffer.alloc(0))).toThrow(/No llegó ningún archivo/);
    });

    it('pasado el tamaño, el mensaje dice cuánto se admite', () => {
      const enorme = Buffer.concat([JPEG, Buffer.alloc(MAXIMO_BYTES_DOCUMENTO)]);
      expect(() => comprobarArchivo(enorme)).toThrow(/pasa de 15 MB/);
    });

    it('el nombre del fichero se queda sin rutas ni vacíos', () => {
      expect(nombreLimpio('C:\\fotos\\albarán.jpg', 'jpg')).toBe('albarán.jpg');
      expect(nombreLimpio('/tmp/../etc/passwd', 'pdf')).toBe('passwd');
      expect(nombreLimpio('   ', 'png')).toBe('documento.png');
      expect(nombreLimpio(undefined, 'pdf')).toBe('documento.pdf');
      expect(nombreLimpio('a'.repeat(500), 'jpg').length).toBe(200);
    });
  });

  describe('dónde se guarda', () => {
    it('la clave lleva la organización y el año y mes, y el id como nombre', () => {
      const clave = claveDocumento({
        organizationId: 'org-1',
        documentId: 'doc-1',
        extension: 'jpg',
        subidoEl: new Date('2026-09-23T10:00:00Z'),
      });
      expect(clave).toBe('documents/org-1/2026/09/doc-1.jpg');
    });

    it('el nombre del objeto no es el que escribió el usuario', () => {
      const clave = claveDocumento({
        organizationId: 'org-1',
        documentId: 'doc-1',
        extension: 'pdf',
        subidoEl: new Date('2026-01-05T00:00:00Z'),
      });
      expect(clave).not.toContain('factura');
      expect(clave).toBe('documents/org-1/2026/01/doc-1.pdf');
    });
  });

  describe('lo que acompaña al archivo', () => {
    async function errores(dto: object) {
      const lista = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
      return lista.map((e) => e.property);
    }

    it('sin nada, vale: el tipo por defecto es una foto', async () => {
      await expect(errores(plainToInstance(DocumentUploadDto, {}))).resolves.toEqual([]);
    });

    it('un tipo inventado no pasa', async () => {
      const malo = plainToInstance(DocumentUploadDto, { documentType: 'selfie' });
      await expect(errores(malo)).resolves.toEqual(['documentType']);
    });

    it('acepta los tipos del cuaderno', async () => {
      const bueno = plainToInstance(DocumentUploadDto, {
        documentType: 'delivery_note',
        title: 'Albarán de la cooperativa',
      });
      await expect(errores(bueno)).resolves.toEqual([]);
    });
  });

  describe('protección de la API', () => {
    it('los documentos exigen la función contratada', () => {
      expect(Reflect.getMetadata(REQUIRE_FEATURE_KEY, DocumentsController)).toEqual(['campaigns']);
    });

    it('verlos es leer; adjuntar y quitar es registrar lo que se hace', () => {
      const permisoDe = (metodo: keyof DocumentsController) =>
        Reflect.getMetadata(REQUIRE_PERMISSION_KEY, DocumentsController.prototype[metodo]);

      expect(permisoDe('list')).toBe('campaigns.read');
      for (const metodo of [
        'upload',
        'remove',
        'uploadToActivity',
        'removeFromActivity',
      ] as const) {
        expect(permisoDe(metodo)).toBe('campaigns.record');
      }
    });
  });
});
