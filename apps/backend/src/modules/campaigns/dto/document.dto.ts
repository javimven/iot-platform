import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { TIPOS_DE_DOCUMENTO } from '../document.rules';

/**
 * Lo que acompaña al archivo en la subida. Va en el mismo `multipart`, así que
 * todo llega como texto: nada de números ni booleanos aquí.
 *
 * El archivo en sí no se valida con `class-validator` (no es un campo del
 * cuerpo): lo comprueba `comprobarArchivo` mirando sus primeros bytes.
 */
export class DocumentUploadDto {
  /** Qué es. Por defecto una foto, que es lo que más se sube desde el campo. */
  @IsOptional()
  @IsIn(TIPOS_DE_DOCUMENTO)
  documentType?: (typeof TIPOS_DE_DOCUMENTO)[number];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string;
}
