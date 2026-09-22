import { Controller, Get } from '@nestjs/common';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { PrismaService } from '../../common/prisma/prisma.service';

/**
 * Catálogo de cultivos (migración 0010). Es de plataforma, no de ninguna
 * organización, y pequeño: se devuelve entero y la app filtra mientras se
 * escribe (así "platano" encuentra "Plátano", cosa que un `ILIKE` no hace sin
 * la extensión `unaccent`).
 *
 * Solo lo activo. Los códigos EPPO/SIEX no salen: el agricultor ve
 * "Aguacate", no un código (ADR-0014).
 */
@RequireFeature('campaigns')
@Controller('crops')
export class CropsController {
  constructor(private readonly prisma: PrismaService) {}

  @RequirePermission('campaigns.read')
  @Get()
  list() {
    return this.prisma.crop.findMany({
      where: { active: true },
      select: { id: true, name: true, category: true },
      orderBy: { name: 'asc' },
    });
  }
}
