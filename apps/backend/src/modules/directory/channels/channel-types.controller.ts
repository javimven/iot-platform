import { Controller, Get } from '@nestjs/common';
import { PrismaService } from '../../../common/prisma/prisma.service';

/** Catálogo de plataforma (DATA_MODEL.md §4), de solo lectura para cualquier usuario autenticado. */
@Controller('channel-types')
export class ChannelTypesController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  findAll() {
    return this.prisma.channelType.findMany({ orderBy: { code: 'asc' } });
  }
}
