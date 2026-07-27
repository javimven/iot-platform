import { IsBoolean, IsString } from 'class-validator';

/** OPENAPI.yaml PUT /platform/organizations/{id}/features — body es un array plano. */
export class FeatureUpdateItem {
  @IsString()
  featureCode!: string;

  @IsBoolean()
  enabled!: boolean;
}
