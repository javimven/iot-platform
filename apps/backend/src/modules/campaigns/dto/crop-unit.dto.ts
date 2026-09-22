import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';

/**
 * Conjuntos cerrados de la unidad de cultivo. Los mismos que los CHECK de la
 * migración 0010: si se amplía uno, se amplían los dos.
 */
export const REGIMENES_HIDRICOS = ['rainfed', 'irrigated'] as const;
export const ENTORNOS_DE_CULTIVO = ['open_field', 'greenhouse', 'other'] as const;
export const SISTEMAS_PRODUCTIVOS = ['conventional', 'integrated', 'organic'] as const;

/** Mismo formato que `crops.id` (CHECK `crops_id_es_slug`). */
export const FORMATO_ID_CULTIVO = /^[a-z0-9_]+$/;

/** Una parcela de la unidad y, si no es entera, cuánta superficie ocupa. */
export class CropUnitParcelDto {
  @IsUUID()
  parcelId!: string;

  /** Nulo u omitido = la parcela entera. */
  @IsOptional()
  @IsNumber()
  @Min(0.0001)
  @Max(100000)
  areaHa?: number;
}

class CamposDeUnidad {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  variety?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  previousCrop?: string;

  @IsOptional()
  @IsIn(REGIMENES_HIDRICOS)
  waterRegime?: (typeof REGIMENES_HIDRICOS)[number];

  @IsOptional()
  @IsIn(ENTORNOS_DE_CULTIVO)
  growingEnvironment?: (typeof ENTORNOS_DE_CULTIVO)[number];

  @IsOptional()
  @IsIn(SISTEMAS_PRODUCTIVOS)
  productionSystem?: (typeof SISTEMAS_PRODUCTIVOS)[number];

  /** Superficie cultivada declarada. Sin ella, la suma de sus parcelas. */
  @IsOptional()
  @IsNumber()
  @Min(0.0001)
  @Max(100000)
  areaHa?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(10000000)
  expectedYieldKgHa?: number;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  notes?: string;
}

/**
 * Una unidad de cultivo al crear una campaña o al añadirla después. El
 * cultivo, del catálogo (`cropId`) o escrito a mano (`cropName`) si no está.
 */
export class CropUnitCreateDto extends CamposDeUnidad {
  @IsOptional()
  @IsString()
  @Matches(FORMATO_ID_CULTIVO)
  cropId?: string;

  /** Obligatorio si no se da `cropId`; con `cropId`, se toma el del catálogo. */
  @ValidateIf((unidad: CropUnitCreateDto) => !unidad.cropId || unidad.cropName !== undefined)
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  cropName?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => CropUnitParcelDto)
  parcels!: CropUnitParcelDto[];
}

/**
 * Cambios en una unidad. `parcels`, si viene, es la lista completa: las que no
 * estén se quitan (y no se puede quitar una con actividades registradas).
 */
export class CropUnitUpdateDto extends CamposDeUnidad {
  @IsOptional()
  @IsString()
  @Matches(FORMATO_ID_CULTIVO)
  cropId?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  cropName?: string;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => CropUnitParcelDto)
  parcels?: CropUnitParcelDto[];
}
