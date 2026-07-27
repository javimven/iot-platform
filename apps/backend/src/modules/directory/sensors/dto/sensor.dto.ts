import { IsOptional, IsString, MinLength } from 'class-validator';

export class SensorCreateDto {
  @IsString()
  @MinLength(1)
  externalIdentifier!: string;

  @IsOptional()
  @IsString()
  label?: string;
}
