import { IsString, IsUUID } from 'class-validator';

export class SelectOrganizationDto {
  @IsString()
  preAuthToken!: string;

  @IsUUID()
  organizationId!: string;
}
