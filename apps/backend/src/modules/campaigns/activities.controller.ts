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
import { ActivitiesService } from './activities.service';
import { CampaignSummaryService } from './campaign-summary';
import {
  ActivityCreateDto,
  ActivityDeleteQueryDto,
  ActivityListQueryDto,
  ActivityUpdateDto,
} from './dto/activity.dto';

/**
 * Actividades de una campaña y su resumen (BACKLOG.md #60, fase 3). Leer va
 * con `campaigns.read`; registrar, cambiar y borrar, con `campaigns.record`,
 * que tiene también el Operador: quien trabaja en el campo apunta lo que hace.
 *
 * Una sola ruta de alta para todos los tipos, con el cuerpo discriminado por
 * `type`: rutas separadas por tipo triplicarían la API sin validar mejor.
 */
@RequireFeature('campaigns')
@Controller('campaigns/:id')
export class ActivitiesController {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly resumen: CampaignSummaryService,
  ) {}

  @RequirePermission('campaigns.read')
  @Get('activities')
  list(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() filtros: ActivityListQueryDto,
  ) {
    return this.activities.list(user, id, filtros);
  }

  @RequirePermission('campaigns.record')
  @Post('activities')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ActivityCreateDto,
  ) {
    return this.activities.create(user, id, dto);
  }

  @RequirePermission('campaigns.read')
  @Get('activities/:activityId')
  findOne(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('activityId', ParseUUIDPipe) activityId: string,
  ) {
    return this.activities.findOne(user, id, activityId);
  }

  @RequirePermission('campaigns.record')
  @Patch('activities/:activityId')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('activityId', ParseUUIDPipe) activityId: string,
    @Body() dto: ActivityUpdateDto,
  ) {
    return this.activities.update(user, id, activityId, dto);
  }

  /** El motivo va en la consulta: un cuerpo en un DELETE lo tiran algunos proxies. */
  @RequirePermission('campaigns.record')
  @Delete('activities/:activityId')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('activityId', ParseUUIDPipe) activityId: string,
    @Query() consulta: ActivityDeleteQueryDto,
  ) {
    await this.activities.remove(user, id, activityId, consulta.reason);
  }

  @RequirePermission('campaigns.read')
  @Get('summary')
  summary(@CurrentUser() user: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.resumen.summary(user, id);
  }
}
