import { Controller, Get } from '@nestjs/common';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';

/**
 * Catálogo completo de funciones (`features`, `PERMISSIONS.md` §14) — sin
 * esto, `GET /platform/organizations/{id}/features` (que solo devuelve las
 * filas `organization_features` ya existentes) es inútil para una
 * organización que nunca ha tenido ninguna activada: no hay forma de saber
 * qué funciones existen para poder activarlas por primera vez. Encontrado
 * al construir el editor de funciones del panel de plataforma en Flutter
 * (Etapa 14). Mismo patrón simple que `ChannelTypesController` (catálogo de
 * solo lectura, sin servicio dedicado).
 */
@Controller('platform/features')
export class PlatformFeaturesCatalogController {
  constructor(private readonly prisma: PrismaService) {}

  @RequirePermission('org_features.read')
  @Get()
  findAll() {
    return this.prisma.feature.findMany({ orderBy: { code: 'asc' } });
  }
}
