import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { InstallationsService } from './installations.service';
import { InstallationCreateDto, InstallationUpdateDto } from './dto/installation.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** API_DESIGN.md §2: ruta de miembro, organización siempre implícita del JWT. */
@Controller('installations')
export class InstallationsController {
  constructor(private readonly installations: InstallationsService) {}

  @RequirePermission('installations.create')
  @Post()
  create(@CurrentUser() user: AccessTokenClaims, @Body() dto: InstallationCreateDto) {
    return this.installations.create(user, dto);
  }

  @RequirePermission('installations.read')
  @Get()
  findAll(@CurrentUser() user: AccessTokenClaims) {
    return this.installations.findAll(user);
  }

  @RequirePermission('installations.read')
  @Get(':id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.installations.findOne(user, id);
  }

  @RequirePermission('installations.update')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: InstallationUpdateDto,
  ) {
    return this.installations.update(user, id, dto);
  }

  @RequirePermission('installations.delete')
  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.installations.softDelete(user, id);
  }
}
