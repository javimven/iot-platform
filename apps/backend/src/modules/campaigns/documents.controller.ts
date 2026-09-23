import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { MAXIMO_BYTES_DOCUMENTO } from './document.rules';
import { DocumentsService } from './documents.service';
import { DocumentUploadDto } from './dto/document.dto';

/** Lo que llega de multer con el archivo en memoria. */
interface ArchivoSubido {
  buffer?: Buffer;
  originalname?: string;
}

/**
 * Fotos y documentos del cuaderno (BACKLOG.md #60, fase 6).
 *
 * **Van por `multipart`, con el archivo en memoria**: nada se escribe en el
 * disco de la VPS, que tiene poco sitio y ya se llenó una vez dejando la
 * plataforma tres días sin ingerir (BACKLOG.md #54). El tope lo pone multer
 * aquí, además de la comprobación de `document.rules`, para cortar la subida
 * en cuanto se pasa en vez de leerla entera.
 *
 * Adjuntar es registrar lo que se ha hecho, así que va con `campaigns.record`:
 * el Operador que está en el campo puede hacer la foto del albarán.
 */
@RequireFeature('campaigns')
@Controller('campaigns/:id')
export class DocumentsController {
  constructor(private readonly documentos: DocumentsService) {}

  @RequirePermission('campaigns.read')
  @Get('documents')
  list(@CurrentUser() user: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.documentos.listar(user, id);
  }

  @RequirePermission('campaigns.record')
  @Post('documents')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAXIMO_BYTES_DOCUMENTO } }))
  upload(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() file: ArchivoSubido | undefined,
    @Body() dto: DocumentUploadDto,
  ) {
    return this.documentos.subir(user, { campaignId: id }, file, dto);
  }

  @RequirePermission('campaigns.record')
  @Delete('documents/:documentId')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('documentId', ParseUUIDPipe) documentId: string,
  ) {
    await this.documentos.quitar(user, { campaignId: id }, documentId);
  }

  @RequirePermission('campaigns.record')
  @Post('activities/:activityId/documents')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAXIMO_BYTES_DOCUMENTO } }))
  uploadToActivity(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('activityId', ParseUUIDPipe) activityId: string,
    @UploadedFile() file: ArchivoSubido | undefined,
    @Body() dto: DocumentUploadDto,
  ) {
    return this.documentos.subir(user, { campaignId: id, activityId }, file, dto);
  }

  @RequirePermission('campaigns.record')
  @Delete('activities/:activityId/documents/:documentId')
  @HttpCode(204)
  async removeFromActivity(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('activityId', ParseUUIDPipe) activityId: string,
    @Param('documentId', ParseUUIDPipe) documentId: string,
  ) {
    await this.documentos.quitar(user, { campaignId: id, activityId }, documentId);
  }
}
