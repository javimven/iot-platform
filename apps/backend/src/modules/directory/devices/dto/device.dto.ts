import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class DeviceCreateDto {
  @IsUUID()
  zoneId!: string;

  @IsString()
  @MinLength(1)
  externalIdentifier!: string;

  @IsString()
  @MinLength(1)
  name!: string;
}

export class DeviceUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @IsOptional()
  @IsUUID()
  zoneId?: string;
}
