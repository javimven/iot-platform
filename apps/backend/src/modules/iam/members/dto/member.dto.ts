import { IsEmail, IsEnum, IsOptional, IsUUID } from 'class-validator';
import { ROLE_CODES, RoleCode } from '../../../../common/permissions/permissions';

export class MemberInviteDto {
  @IsEmail()
  email!: string;

  @IsEnum(ROLE_CODES)
  roleCode!: RoleCode;
}

export class MemberUpdateDto {
  @IsOptional()
  @IsEnum(ROLE_CODES)
  roleCode?: RoleCode;

  @IsOptional()
  @IsEnum(['active', 'suspended'])
  status?: 'active' | 'suspended';
}

export class MemberScopeDto {
  @IsUUID(undefined, { each: true })
  installationIds!: string[];
}
