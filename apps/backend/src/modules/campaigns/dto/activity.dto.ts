import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
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

/**
 * Actividades del cuaderno (ADR-0012). Los conjuntos cerrados son los de los
 * CHECK de la migración 0011; los que acabarán siendo códigos de un catálogo
 * oficial del SIEX (sistema de riego, material, método de aplicación, tipo de
 * labor) se validan aquí y se mapearán sin migración (ADR-0014).
 *
 * **Nada de lo del cuaderno completo es obligatorio para guardar** (ADR-0013):
 * quien está en el campo tiene que poder apuntar un tratamiento en segundos y
 * completarlo después. Lo que falta lo marca el indicador de completitud y se
 * avisa al cerrar. Lo que sí se rechaza es lo incoherente.
 */
export const TIPOS_DE_ACTIVIDAD = [
  'irrigation',
  'fertilization',
  'phytosanitary',
  'field_work',
  'harvest',
  'observation',
  'sowing',
  'other',
] as const;
export type TipoDeActividad = (typeof TIPOS_DE_ACTIVIDAD)[number];

/** Sistemas de riego del bloque 10 del CUE. */
export const SISTEMAS_DE_RIEGO = [
  'surface',
  'sprinkler_fixed',
  'sprinkler_mobile',
  'micro_sprinkler',
  'fogging',
  'drip',
  'hydroponic_open',
  'hydroponic_recirculating',
] as const;
export const UNIDADES_DE_RIEGO = ['m3', 'm3_ha', 'l'] as const;

export const TIPOS_DE_FERTILIZACION = ['base', 'top_dressing', 'amendment', 'other'] as const;
export const MATERIALES_FERTILIZANTES = [
  'fertilizer_product',
  'solid_manure',
  'slurry',
  'sewage_sludge',
  'compost_digestate',
  'other_waste',
  'other',
] as const;
export const METODOS_DE_APLICACION = [
  'broadcast',
  'localized',
  'fertigation',
  'foliar',
  'injection',
  'other',
] as const;
export const UNIDADES_DE_DOSIS_FERTILIZANTE = [
  'kg_ha',
  'l_ha',
  't_ha',
  'm3_ha',
  'kg',
  'l',
  't',
  'm3',
] as const;

export const CATEGORIAS_DE_PROBLEMA = [
  'weeds',
  'diseases',
  'arthropods',
  'growth_regulators',
  'other',
] as const;
export const EFICACIAS = ['good', 'fair', 'poor'] as const;
export const UNIDADES_DE_DOSIS_FITOSANITARIA = ['l_ha', 'kg_ha', 'l_hl', 'kg_hl'] as const;
export const UNIDADES_DE_CANTIDAD_FITOSANITARIA = ['l', 'kg'] as const;

export const UNIDADES_DE_COSECHA = ['kg', 't', 'units'] as const;

export const TIPOS_DE_LABOR = [
  'soil_preparation',
  'tillage',
  'pruning',
  'clearing',
  'mowing',
  'shredding',
  'thinning',
  'grafting',
  'cover_management',
  'mechanical_control',
  'maintenance',
  'other',
] as const;

/** Sobre qué parcela, y cuánta superficie si no es toda. */
export class ActivityTargetDto {
  @IsUUID()
  parcelId!: string;

  /** Solo hace falta si la parcela está en más de una unidad de la campaña. */
  @IsOptional()
  @IsUUID()
  cropUnitId?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.0001)
  @Max(100000)
  areaHa?: number;
}

export class IrrigationDetailDto {
  @IsOptional()
  @IsIn(SISTEMAS_DE_RIEGO)
  system?: (typeof SISTEMAS_DE_RIEGO)[number];

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(10000000)
  amount?: number;

  @IsOptional()
  @IsIn(UNIDADES_DE_RIEGO)
  amountUnit?: (typeof UNIDADES_DE_RIEGO)[number];

  @IsOptional()
  @IsString()
  @MaxLength(120)
  waterSource?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  meterNumber?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100000)
  nitrateMgL?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100000)
  p2o5MgL?: number;
}

export class FertilizationDetailDto {
  @IsOptional()
  @IsIn(TIPOS_DE_FERTILIZACION)
  fertilizationType?: (typeof TIPOS_DE_FERTILIZACION)[number];

  @IsOptional()
  @IsIn(MATERIALES_FERTILIZANTES)
  materialType?: (typeof MATERIALES_FERTILIZANTES)[number];

  @IsOptional()
  @IsString()
  @MaxLength(160)
  productName?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(10000000)
  dose?: number;

  @IsOptional()
  @IsIn(UNIDADES_DE_DOSIS_FERTILIZANTE)
  doseUnit?: (typeof UNIDADES_DE_DOSIS_FERTILIZANTE)[number];

  @IsOptional()
  @IsIn(METODOS_DE_APLICACION)
  applicationMethod?: (typeof METODOS_DE_APLICACION)[number];

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  nPct?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  p2o5Pct?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  k2oPct?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  organicMatterPct?: number;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  supplierName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  supplierNif?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  supplierRega?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  supplierNima?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  applicatorCompany?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  regferCode?: string;

  @IsOptional()
  @IsUUID()
  equipmentId?: string;
}

export class PhytosanitaryProductDto {
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  productName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  registryNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(400)
  activeSubstances?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100000)
  dose?: number;

  @IsOptional()
  @IsIn(UNIDADES_DE_DOSIS_FITOSANITARIA)
  doseUnit?: (typeof UNIDADES_DE_DOSIS_FITOSANITARIA)[number];

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1000000)
  totalQuantity?: number;

  @IsOptional()
  @IsIn(UNIDADES_DE_CANTIDAD_FITOSANITARIA)
  totalQuantityUnit?: (typeof UNIDADES_DE_CANTIDAD_FITOSANITARIA)[number];
}

export class PhytosanitaryDetailDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  problem?: string;

  @IsOptional()
  @IsIn(CATEGORIAS_DE_PROBLEMA)
  problemCategory?: (typeof CATEGORIAS_DE_PROBLEMA)[number];

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  justification?: string;

  /** Código BBCH de dos cifras; la app enseña el nombre ("Floración"). */
  @IsOptional()
  @IsString()
  @Matches(/^\d{2}$/)
  bbchCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  phenologicalStageLabel?: string;

  @IsOptional()
  @IsUUID()
  applicatorId?: string;

  @IsOptional()
  @IsUUID()
  adviserId?: string;

  @IsOptional()
  @IsUUID()
  equipmentId?: string;

  @IsOptional()
  @IsBoolean()
  manualApplication?: boolean;

  @IsOptional()
  @IsIn(EFICACIAS)
  efficacy?: (typeof EFICACIAS)[number];

  /** Uno o varios (una mezcla en el mismo depósito). */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => PhytosanitaryProductDto)
  products!: PhytosanitaryProductDto[];
}

export class HarvestDetailDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  product?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1000000000)
  quantity?: number;

  @IsOptional()
  @IsIn(UNIDADES_DE_COSECHA)
  quantityUnit?: (typeof UNIDADES_DE_COSECHA)[number];

  @IsOptional()
  @IsString()
  @MaxLength(80)
  lotCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deliveryNote?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  customerName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  customerNif?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  customerAddress?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  customerRgseaa?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  destination?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  qualityGrade?: string;
}

export class FieldWorkDetailDto {
  @IsIn(TIPOS_DE_LABOR)
  workType!: (typeof TIPOS_DE_LABOR)[number];

  @IsOptional()
  @IsBoolean()
  pruningResiduesLeft?: boolean;

  @IsOptional()
  @IsBoolean()
  clearingResiduesLeft?: boolean;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(10000)
  hours?: number;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  machinery?: string;
}

/** Lo común a cualquier actividad, al crear y al cambiar. */
class CamposDeActividad {
  @IsOptional()
  @EsFecha()
  endDate?: string;

  /** Hora de inicio, `HH:mm`, en hora de la finca. */
  @IsOptional()
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  startTime?: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  notes?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => IrrigationDetailDto)
  irrigation?: IrrigationDetailDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => FertilizationDetailDto)
  fertilization?: FertilizationDetailDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => PhytosanitaryDetailDto)
  phytosanitary?: PhytosanitaryDetailDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => HarvestDetailDto)
  harvest?: HarvestDetailDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => FieldWorkDetailDto)
  fieldWork?: FieldWorkDetailDto;
}

export class ActivityCreateDto extends CamposDeActividad {
  @IsIn(TIPOS_DE_ACTIVIDAD)
  type!: TipoDeActividad;

  @EsFecha()
  startDate!: string;

  /** Una actividad sobre tres parcelas es un registro con tres destinos. */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => ActivityTargetDto)
  targets!: ActivityTargetDto[];

  /** "Repetir": de qué actividad se copió (y se confirmó) esta. */
  @IsOptional()
  @IsUUID()
  repeatedFromId?: string;
}

/**
 * Cambios en una actividad. El tipo no cambia (sería otra actividad). El
 * detalle, si viene, sustituye al anterior entero; los destinos, igual.
 */
export class ActivityUpdateDto extends CamposDeActividad {
  @IsOptional()
  @EsFecha()
  startDate?: string;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => ActivityTargetDto)
  targets?: ActivityTargetDto[];
}

export class ActivityListQueryDto {
  @IsOptional()
  @IsIn(TIPOS_DE_ACTIVIDAD)
  type?: TipoDeActividad;

  @IsOptional()
  @EsFecha()
  from?: string;

  @IsOptional()
  @EsFecha()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  limit?: number;
}

export class ActivityDeleteQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  reason?: string;
}
