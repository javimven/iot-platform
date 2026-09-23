import { Controller, Get, Param, ParseUUIDPipe, Query, Res } from '@nestjs/common';
import { IsIn, IsOptional } from 'class-validator';
import type { Response } from 'express';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { CampaignExportService, FormatoDeExportacion } from './export.service';
import { DisposicionDelPdf } from './export-pdf';

export class ExportQueryDto {
  /** Por defecto PDF: es lo que se quiere el 90 % de las veces. */
  @IsOptional()
  @IsIn(['pdf', 'json', 'csv'])
  format?: FormatoDeExportacion;

  /**
   * Cómo se dispone el PDF: `informe` (para leerlo) o `cue` (en el orden de
   * los apartados del Cuaderno Único de Explotación). No aplica a JSON ni CSV.
   */
  @IsOptional()
  @IsIn(['informe', 'cue'])
  layout?: DisposicionDelPdf;
}

/**
 * Exportar el cuaderno (BACKLOG.md #60, fase 7). Exportar es leer: va con
 * `campaigns.read` y no tiene permiso propio (PERMISSIONS.md §14 ter).
 *
 * Devuelve el fichero, no un enlace: el cuaderno se genera en el momento a
 * partir de lo registrado (o de la instantánea, si la campaña está cerrada), y
 * guardarlo en el bucket dejaría copias que envejecen.
 */
@RequireFeature('campaigns')
@Controller('campaigns/:id')
export class CampaignExportController {
  constructor(private readonly exportacion: CampaignExportService) {}

  @RequirePermission('campaigns.read')
  @Get('export')
  async export(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() consulta: ExportQueryDto,
    @Res() res: Response,
  ): Promise<void> {
    const fichero = await this.exportacion.exportar(user, id, {
      formato: consulta.format ?? 'pdf',
      disposicion: consulta.layout,
    });

    res.setHeader('Content-Type', fichero.mediaType);
    res.setHeader('Content-Length', fichero.bytes.byteLength);
    // `filename*` en UTF-8 porque el nombre lleva el del cultivo, con acentos;
    // `filename` a secas queda de reserva para clientes antiguos.
    const ascii = fichero.filename.replace(/[^\x20-\x7e]/g, '_');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(fichero.filename)}`,
    );
    res.end(fichero.bytes);
  }
}
