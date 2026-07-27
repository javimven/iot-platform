import {
  IsEnum,
  IsInt,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  MinLength,
} from 'class-validator';
import { ConnectivityType } from '@prisma/client';

export class GatewayCreateDto {
  @IsUUID()
  installationId!: string;

  @IsString()
  @MinLength(1)
  name!: string;

  /** ADR-0004: concentrador LoRa o estación de conexión directa (NB-IoT u otra). */
  @IsEnum(ConnectivityType)
  connectivityType!: ConnectivityType;
}

export class GatewayUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @IsOptional()
  @IsInt()
  @IsPositive()
  heartbeatIntervalSeconds?: number;
}
