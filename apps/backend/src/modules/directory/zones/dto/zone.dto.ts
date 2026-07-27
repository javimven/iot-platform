import { IsOptional, IsString, MinLength } from 'class-validator';

export class ZoneCreateDto {
  @IsString()
  @MinLength(1)
  name!: string;

  @IsOptional()
  @IsString()
  zoneType?: string;
}

export class ZoneUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @IsOptional()
  @IsString()
  zoneType?: string;
}
