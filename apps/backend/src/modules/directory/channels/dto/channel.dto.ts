import { IsNumber, IsOptional } from 'class-validator';

export class ChannelUpdateThresholdDto {
  @IsOptional()
  @IsNumber()
  alertThresholdMin?: number;

  @IsOptional()
  @IsNumber()
  alertThresholdMax?: number;
}
