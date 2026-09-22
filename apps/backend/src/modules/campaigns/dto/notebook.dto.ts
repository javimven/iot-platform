import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { EsFecha } from '../fechas';

/**
 * Catálogos del cuaderno completo: las personas que tratan o asesoran y los
 * equipos de aplicación (migración 0011). Se dan de alta una vez y se eligen
 * después al registrar un tratamiento, en vez de teclearlos cada vez.
 *
 * Los mismos conjuntos cerrados que los CHECK de la migración.
 */
export const TIPOS_DE_PERSONA = ['own_staff', 'service_company', 'adviser'] as const;

/** `null` explícito = deja de estar limitada a una finca (vale para todas). */
const ID_DE_FINCA = () =>
  Transform(({ value }) => (value === null || value === '' ? null : value), {
    toClassOnly: true,
  });

class CamposDePersona {
  /** Nulo = sirve para todas las fincas de la organización. */
  @IsOptional()
  @ID_DE_FINCA()
  @IsUUID()
  installationId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  surname1?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  surname2?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  companyName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  nif?: string;

  /** Inscripción en el ROPO. Texto libre: los formatos varían por comunidad. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  ropoNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  ropoCardType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

export class NotebookPersonCreateDto extends CamposDePersona {
  @IsIn(TIPOS_DE_PERSONA)
  kind!: (typeof TIPOS_DE_PERSONA)[number];
}

export class NotebookPersonUpdateDto extends CamposDePersona {
  @IsOptional()
  @IsIn(TIPOS_DE_PERSONA)
  kind?: (typeof TIPOS_DE_PERSONA)[number];
}

class CamposDeEquipo {
  @IsOptional()
  @ID_DE_FINCA()
  @IsUUID()
  installationId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  brand?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  model?: string;

  /** Inscripción en el ROMA (Registro Oficial de Maquinaria Agrícola). */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  romaNumber?: string;

  @IsOptional()
  @EsFecha()
  acquiredOn?: string;

  /** Última inspección ITEAF, cuando el equipo la tiene. */
  @IsOptional()
  @EsFecha()
  lastInspectionOn?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

export class NotebookEquipmentCreateDto extends CamposDeEquipo {
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  description!: string;
}

export class NotebookEquipmentUpdateDto extends CamposDeEquipo {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  description?: string;
}

export class NotebookListQueryDto {
  /** Las de esa finca más las que valen para todas. */
  @IsOptional()
  @IsUUID()
  installationId?: string;

  @IsOptional()
  @IsIn(TIPOS_DE_PERSONA)
  kind?: (typeof TIPOS_DE_PERSONA)[number];

  /** `true` incluye las dadas de baja, para poder consultarlas. */
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  includeDeleted?: boolean;
}
