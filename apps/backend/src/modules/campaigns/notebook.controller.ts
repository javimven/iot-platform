import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import {
  NotebookEquipmentCreateDto,
  NotebookEquipmentUpdateDto,
  NotebookListQueryDto,
  NotebookPersonCreateDto,
  NotebookPersonUpdateDto,
} from './dto/notebook.dto';
import { NotebookCatalogService } from './notebook.service';

/**
 * Catálogos del cuaderno completo (fase 5 del #60): personas y equipos.
 *
 * Elegirlos al registrar una actividad es leer (`campaigns.read`, que tiene
 * también el Operador); mantenerlos es configurar la explotación
 * (`campaigns.update`), como las unidades de cultivo.
 */
@RequireFeature('campaigns')
@Controller('notebook')
export class NotebookController {
  constructor(private readonly catalogo: NotebookCatalogService) {}

  @RequirePermission('campaigns.read')
  @Get('people')
  listPeople(@CurrentUser() user: AccessTokenClaims, @Query() filtros: NotebookListQueryDto) {
    return this.catalogo.listPeople(user, filtros);
  }

  @RequirePermission('campaigns.update')
  @Post('people')
  createPerson(@CurrentUser() user: AccessTokenClaims, @Body() dto: NotebookPersonCreateDto) {
    return this.catalogo.createPerson(user, dto);
  }

  @RequirePermission('campaigns.update')
  @Patch('people/:id')
  updatePerson(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: NotebookPersonUpdateDto,
  ) {
    return this.catalogo.updatePerson(user, id, dto);
  }

  @RequirePermission('campaigns.update')
  @Delete('people/:id')
  @HttpCode(204)
  async removePerson(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    await this.catalogo.removePerson(user, id);
  }

  @RequirePermission('campaigns.read')
  @Get('equipment')
  listEquipment(@CurrentUser() user: AccessTokenClaims, @Query() filtros: NotebookListQueryDto) {
    return this.catalogo.listEquipment(user, filtros);
  }

  @RequirePermission('campaigns.update')
  @Post('equipment')
  createEquipment(@CurrentUser() user: AccessTokenClaims, @Body() dto: NotebookEquipmentCreateDto) {
    return this.catalogo.createEquipment(user, dto);
  }

  @RequirePermission('campaigns.update')
  @Patch('equipment/:id')
  updateEquipment(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: NotebookEquipmentUpdateDto,
  ) {
    return this.catalogo.updateEquipment(user, id, dto);
  }

  @RequirePermission('campaigns.update')
  @Delete('equipment/:id')
  @HttpCode(204)
  async removeEquipment(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    await this.catalogo.removeEquipment(user, id);
  }
}
