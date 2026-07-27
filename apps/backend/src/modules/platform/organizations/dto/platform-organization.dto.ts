import { IsEmail, IsString, MinLength } from 'class-validator';

export class PlatformOrganizationCreateDto {
  @IsString()
  @MinLength(1)
  name!: string;

  @IsEmail()
  contactEmail!: string;

  @IsEmail()
  firstAdminEmail!: string;
}
