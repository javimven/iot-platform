import { createHash, randomUUID } from 'node:crypto';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { claveDocumento } from '../../common/storage/object-keys';
import { StorageService } from '../../common/storage/storage.service';
import { CampaignAccess } from './campaign-access';
import { comprobarArchivo, nombreLimpio } from './document.rules';
import { DocumentUploadDto } from './dto/document.dto';

/** A qué se engancha el documento: o a la campaña, o a una de sus actividades. */
export interface DestinoDeDocumento {
  campaignId: string;
  activityId?: string;
}

type DocumentoConEnlaces = Prisma.DocumentGetPayload<{ include: { links: true } }>;

/**
 * Documentos y fotos del cuaderno (BACKLOG.md #60, fase 6).
 *
 * Lo que hace que esto sea barato de mantener:
 *
 * - **Un solo almacenamiento**: el mismo `StorageService` y el mismo bucket
 *   privado que el satélite. Nada sale sin una URL firmada que caduca.
 * - **Un fichero se guarda una vez**: si alguien sube dos veces la misma foto
 *   (mismo SHA-256) en la misma organización, se reutiliza el documento y solo
 *   se añade el vínculo. La factura del abono que vale para tres tratamientos
 *   ocupa una vez.
 * - **Quitar un documento de una actividad no lo borra de las demás**: se
 *   quita ese vínculo, y solo cuando no queda ninguno se da de baja el
 *   documento.
 * - **Una campaña cerrada no admite adjuntos nuevos**, como no admite
 *   actividades: su cuaderno es historia hasta que se reabra.
 */
@Injectable()
export class DocumentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly acceso: CampaignAccess,
    private readonly storage: StorageService,
  ) {}

  async subir(
    user: AccessTokenClaims,
    destino: DestinoDeDocumento,
    archivo: { buffer?: Buffer; originalname?: string } | undefined,
    dto: DocumentUploadDto,
  ) {
    const campana = await this.acceso.cargar(user, destino.campaignId);
    this.acceso.asegurarAbierta(campana);
    const formato = comprobarArchivo(archivo?.buffer);
    const bytes = archivo!.buffer!;
    const checksum = createHash('sha256').update(bytes).digest('hex');
    const { organizationId, tenantContext } = resolveOrgContext(user);

    await this.comprobarActividad(user, destino);

    // Si ya está guardado, no se vuelve a subir: se reutiliza el objeto.
    const existente = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.document.findFirst({ where: { organizationId, checksum, deletedAt: null } }),
    );

    let documentId = existente?.id;
    let claveSubida: string | undefined;
    if (!existente) {
      documentId = randomUUID();
      claveSubida = claveDocumento({
        organizationId,
        documentId,
        extension: formato.extension,
      });
      await this.storage.subir({
        clave: claveSubida,
        cuerpo: bytes,
        contentType: formato.mediaType,
      });
    }

    try {
      return await this.prisma.runInTenantContext(tenantContext, async (tx) => {
        if (!existente) {
          await tx.document.create({
            data: {
              id: documentId,
              organizationId,
              installationId: campana.installationId,
              documentType: dto.documentType ?? 'photo',
              title: dto.title?.trim() || null,
              filename: nombreLimpio(archivo?.originalname, formato.extension),
              mediaType: formato.mediaType,
              byteSize: bytes.byteLength,
              checksum,
              objectKey: claveSubida!,
              uploadedBy: user.sub,
            },
          });
          await this.auditLog.record(tx, {
            organizationId,
            actorUserId: user.sub,
            action: 'documents.create',
            targetType: 'document',
            targetId: documentId!,
            metadata: {
              documentType: dto.documentType ?? 'photo',
              byteSize: bytes.byteLength,
              mediaType: formato.mediaType,
            },
          });
        }

        // El vínculo puede existir ya (subir dos veces la misma foto a la
        // misma actividad): entonces no se duplica y no pasa nada.
        const yaEnlazado = await tx.documentLink.findFirst({
          where: {
            documentId,
            campaignId: destino.activityId ? null : destino.campaignId,
            activityId: destino.activityId ?? null,
          },
        });
        if (!yaEnlazado) {
          await tx.documentLink.create({
            data: {
              organizationId,
              documentId: documentId!,
              campaignId: destino.activityId ? null : destino.campaignId,
              activityId: destino.activityId ?? null,
              createdBy: user.sub,
            },
          });
          await this.auditLog.record(tx, {
            organizationId,
            actorUserId: user.sub,
            action: 'documents.link',
            targetType: 'document',
            targetId: documentId!,
            metadata: {
              campaignId: destino.campaignId,
              activityId: destino.activityId ?? null,
              reutilizado: Boolean(existente),
            },
          });
        }

        const documento = await tx.document.findUniqueOrThrow({
          where: { id: documentId },
          include: { links: true },
        });
        return this.presentar(documento, destino);
      });
    } catch (error) {
      // La subida fue bien pero la fila no: el objeto quedaría huérfano y
      // nadie sabría de él.
      if (claveSubida) {
        await this.storage.borrar([claveSubida]).catch(() => undefined);
      }
      throw error;
    }
  }

  /** Los documentos de la campaña y los de sus actividades, con su enlace. */
  async listar(user: AccessTokenClaims, campaignId: string) {
    await this.acceso.cargar(user, campaignId);
    const { tenantContext } = resolveOrgContext(user);

    const enlaces = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.documentLink.findMany({
        where: {
          OR: [{ campaignId }, { activity: { campaignId, deletedAt: null } }],
          document: { deletedAt: null },
        },
        include: { document: true },
        orderBy: { createdAt: 'desc' },
      }),
    );

    return Promise.all(
      enlaces.map((enlace) =>
        this.presentar(
          { ...enlace.document, links: [] },
          {
            campaignId,
            activityId: enlace.activityId ?? undefined,
          },
        ),
      ),
    );
  }

  /**
   * Quita el documento de donde estaba. Si no queda en ningún sitio, se da de
   * baja; el objeto se conserva, que es lo que permite auditar qué se subió.
   */
  async quitar(user: AccessTokenClaims, destino: DestinoDeDocumento, documentId: string) {
    const campana = await this.acceso.cargar(user, destino.campaignId);
    this.acceso.asegurarAbierta(campana);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const enlace = await tx.documentLink.findFirst({
        where: {
          documentId,
          campaignId: destino.activityId ? null : destino.campaignId,
          activityId: destino.activityId ?? null,
          document: { deletedAt: null },
        },
      });
      if (!enlace) {
        throw new NotFoundException('Document not found');
      }
      await tx.documentLink.delete({ where: { id: enlace.id } });

      const quedan = await tx.documentLink.count({ where: { documentId } });
      if (quedan === 0) {
        await tx.document.update({
          where: { id: documentId },
          data: { deletedAt: new Date(), deletedBy: user.sub },
        });
      }
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: quedan === 0 ? 'documents.delete' : 'documents.unlink',
        targetType: 'document',
        targetId: documentId,
        metadata: {
          campaignId: destino.campaignId,
          activityId: destino.activityId ?? null,
          enlacesRestantes: quedan,
        },
      });
    });
  }

  /** La actividad tiene que ser de esta campaña y seguir viva. */
  private async comprobarActividad(
    user: AccessTokenClaims,
    destino: DestinoDeDocumento,
  ): Promise<void> {
    if (!destino.activityId) {
      return;
    }
    const { tenantContext } = resolveOrgContext(user);
    const actividad = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.campaignActivity.findFirst({
        where: { id: destino.activityId, campaignId: destino.campaignId, deletedAt: null },
        select: { id: true },
      }),
    );
    if (!actividad) {
      throw new BadRequestException('La actividad no es de esta campaña.');
    }
  }

  private async presentar(documento: DocumentoConEnlaces, destino: DestinoDeDocumento) {
    const enlace = await this.storage.urlFirmada(documento.objectKey);
    return {
      id: documento.id,
      documentType: documento.documentType,
      title: documento.title,
      filename: documento.filename,
      mediaType: documento.mediaType,
      byteSize: documento.byteSize,
      campaignId: destino.campaignId,
      activityId: destino.activityId ?? null,
      uploadedBy: documento.uploadedBy,
      createdAt: documento.createdAt,
      /** Caduca: para verlo más tarde hay que volver a pedir la lista. */
      url: enlace.url,
      urlExpiresAt: enlace.expiresAt,
    };
  }
}
