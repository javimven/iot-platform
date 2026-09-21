import { IsObject, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * El contorno llega como GeoJSON crudo (`@IsObject`): validarlo con
 * decoradores anidados obligaría a modelar Polygon y MultiPolygon como clases
 * y seguiría sin poder comprobar lo que de verdad importa (anillos cerrados,
 * rangos, topología). De eso se encarga `ParcelGeometryService` y, al final,
 * PostGIS — ver ADR-0009.
 */
export class ParcelCreateDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;

  @IsObject()
  geometry!: unknown;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}

export class ParcelUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name?: string;

  /** Redibujar el contorno sube `geometryVersion`. */
  @IsOptional()
  @IsObject()
  geometry?: unknown;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}
