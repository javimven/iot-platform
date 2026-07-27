import { Controller, Get, Inject, ServiceUnavailableException } from '@nestjs/common';
import { Public } from '../decorators/public.decorator';
import { PrismaService } from '../prisma/prisma.service';

/** OBSERVABILITY.md §6: liveness sin dependencias, readiness con dependencias reales. */
@Controller('health')
export class HealthController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Public()
  @Get()
  liveness(): { status: 'ok' } {
    return { status: 'ok' };
  }

  @Public()
  @Get('ready')
  async readiness(): Promise<{ status: 'ok'; checks: Record<string, 'ok'> }> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      throw new ServiceUnavailableException('Database is not reachable');
    }
    return { status: 'ok', checks: { database: 'ok' } };
  }
}
