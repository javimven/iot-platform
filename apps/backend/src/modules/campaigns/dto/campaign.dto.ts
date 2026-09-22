import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { EsFecha } from '../fechas';
import { NotebookProfileDto } from '../notebook-profile';
import { CropUnitCreateDto, FORMATO_ID_CULTIVO } from './crop-unit.dto';

export const MODOS_DE_CAMPANA = ['simple', 'complete'] as const;
export const ESTADOS_DE_CAMPANA = ['draft', 'active', 'closed', 'archived'] as const;

/**
 * Alta de una campaña, con sus unidades de cultivo y parcelas en la misma
 * petición: una campaña sin cultivo ni parcelas no sirve para nada, y así se
 * crea de una vez desde el asistente de la app.
 */
export class CampaignCreateDto {
  @IsIn(MODOS_DE_CAMPANA)
  managementMode!: (typeof MODOS_DE_CAMPANA)[number];

  /** Opcional: si no viene, "Aguacate Hass · 2026". */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  name?: string;

  @EsFecha()
  startDate!: string;

  @IsOptional()
  @EsFecha()
  expectedEndDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  notes?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => CropUnitCreateDto)
  cropUnits!: CropUnitCreateDto[];

  /** Solo en modo completo. */
  @IsOptional()
  @ValidateNested()
  @Type(() => NotebookProfileDto)
  notebookProfile?: NotebookProfileDto;
}

/** Cambios en los datos generales. El estado y el modo tienen sus propias rutas. */
export class CampaignUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  name?: string;

  @IsOptional()
  @EsFecha()
  startDate?: string;

  /** `null` quita la fecha prevista. */
  @IsOptional()
  @EsFecha()
  expectedEndDate?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  notes?: string;

  /** Solo en modo completo. */
  @IsOptional()
  @ValidateNested()
  @Type(() => NotebookProfileDto)
  notebookProfile?: NotebookProfileDto;
}

/** "Completar cuaderno de campo": de sencilla a completa, sin copiar nada. */
export class CampaignUpgradeDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => NotebookProfileDto)
  notebookProfile?: NotebookProfileDto;
}

export class CampaignCloseDto {
  @EsFecha()
  endDate!: string;

  /** Producción final declarada, si no está ya en las cosechas registradas. */
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1000000000)
  declaredProductionKg?: number;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  closingNotes?: string;
}

/** Reabrir una campaña cerrada es corregir un cuaderno: queda auditado con su motivo. */
export class CampaignReopenDto {
  @IsString()
  @MinLength(5)
  @MaxLength(1000)
  reason!: string;
}

export class CampaignListQueryDto {
  @IsOptional()
  @IsIn(ESTADOS_DE_CAMPANA)
  status?: (typeof ESTADOS_DE_CAMPANA)[number];

  @IsOptional()
  @IsUUID()
  installationId?: string;

  /** Campañas que tocan ese año (empiezan antes de que acabe y no acabaron antes de que empiece). */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(2000)
  @Max(2100)
  year?: number;

  @IsOptional()
  @IsString()
  @Matches(FORMATO_ID_CULTIVO)
  cropId?: string;
}

export class CropListQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(60)
  q?: string;
}
