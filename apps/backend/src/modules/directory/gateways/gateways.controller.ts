import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { GatewaysService } from './gateways.service';
import { GatewayCreateDto, GatewayUpdateDto } from './dto/gateway.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** API_DESIGN.md §2 — ruta de miembro, organización implícita del JWT. */
@Controller('gateways')
export class GatewaysController {
  constructor(private readonly gateways: GatewaysService) {}

  @RequirePermission('gateways.create')
  @Post()
  create(@CurrentUser() user: AccessTokenClaims, @Body() dto: GatewayCreateDto) {
    return this.gateways.create(user, dto);
  }

  @RequirePermission('gateways.read')
  @Get()
  findAll(@CurrentUser() user: AccessTokenClaims) {
    return this.gateways.findAll(user);
  }

  @RequirePermission('gateways.read')
  @Get(':id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.gateways.findOne(user, id);
  }

  @RequirePermission('gateways.update')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: GatewayUpdateDto,
  ) {
    return this.gateways.update(user, id, dto);
  }

  @RequirePermission('gateways.disable')
  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.gateways.disable(user, id);
  }

  @RequirePermission('gateways.rotate_credential')
  @Post(':id/rotate-credential')
  rotateCredential(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.gateways.rotateCredential(user, id);
  }
}
