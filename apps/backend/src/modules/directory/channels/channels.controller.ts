import { Body, Controller, Get, Param, Patch } from '@nestjs/common';
import { ChannelsService } from './channels.service';
import { ChannelUpdateThresholdDto } from './dto/channel.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller()
export class ChannelsController {
  constructor(private readonly channels: ChannelsService) {}

  @RequirePermission('channels.read')
  @Get('sensors/:sensorId/channels')
  findAllForSensor(@CurrentUser() user: AccessTokenClaims, @Param('sensorId') sensorId: string) {
    return this.channels.findAllForSensor(user, sensorId);
  }

  @RequirePermission('channels.update_threshold')
  @Patch('channels/:id')
  updateThreshold(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: ChannelUpdateThresholdDto,
  ) {
    return this.channels.updateThreshold(user, id, dto);
  }
}
