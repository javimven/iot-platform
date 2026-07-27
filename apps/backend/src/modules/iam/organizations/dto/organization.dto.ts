import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class OrganizationUpdateDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @IsOptional()
  @IsEmail()
  contactEmail?: string;
}
