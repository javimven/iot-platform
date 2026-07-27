import { Body, Controller, Param, Put } from '@nestjs/common';
import { IsNumber, IsOptional } from 'class-validator';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

class OrgChannelThresholdDto {
  @IsOptional()
  @IsNumber()
  defaultMin?: number;

  @IsOptional()
  @IsNumber()
  defaultMax?: number;
}

/**
 * Umbral por defecto por tipo de canal a nivel de organización
 * (FUNCTIONAL_REQUIREMENTS.md §1, DATA_MODEL.md §4). Reutiliza
 * `channels.update_threshold` (PERMISSIONS.md no distingue un permiso propio
 * para el valor por defecto de organización frente al override por canal —
 * son los mismos actores, Admin de organización y Técnico).
 */
@Controller('organization/channel-thresholds')
export class OrgChannelThresholdsController {
  constructor(private readonly prisma: PrismaService) {}

  @RequirePermission('channels.update_threshold')
  @Put(':channelTypeCode')
  async upsert(
    @CurrentUser() user: AccessTokenClaims,
    @Param('channelTypeCode') channelTypeCode: string,
    @Body() dto: OrgChannelThresholdDto,
  ) {
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.orgChannelThreshold.upsert({
          where: {
            organizationId_channelTypeCode: {
              organizationId: user.organizationId!,
              channelTypeCode,
            },
          },
          create: {
            organizationId: user.organizationId!,
            channelTypeCode,
            defaultMin: dto.defaultMin,
            defaultMax: dto.defaultMax,
          },
          update: { defaultMin: dto.defaultMin, defaultMax: dto.defaultMax },
        }),
    );
  }
}
