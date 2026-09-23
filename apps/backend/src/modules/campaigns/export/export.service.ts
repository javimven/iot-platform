import { Injectable } from '@nestjs/common';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { INCLUDE_ACTIVIDAD } from '../activity.presenter';
import { CampaignAccess } from '../campaign-access';
import { INCLUDE_CAMPANA, presentarDetalle } from '../campaign.presenter';
import { revisar } from '../notebook-completeness';
import { aCsv, aJson, nombreDelFichero } from './export-datos';
import { aPdf, DisposicionDelPdf } from './export-pdf';
import { CabeceraDeInstantanea, construirExportado, CuadernoExportado } from './export-model';

export type FormatoDeExportacion = 'pdf' | 'json' | 'csv';

export interface FicheroExportado {
  bytes: Buffer;
  mediaType: string;
  filename: string;
}

/**
 * Exportar el cuaderno (fase 7 del #60). Exportar es leer, así que va con
 * `campaigns.read`: quien puede ver el cuaderno puede sacarlo.
 *
 * **Una campaña cerrada se exporta desde su instantánea de cierre**
 * (ADR-0012): el titular, la finca y las parcelas son los de aquel día, no los
 * de hoy. Las actividades salen de las tablas porque una campaña cerrada ya no
 * las deja cambiar.
 */
@Injectable()
export class CampaignExportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly acceso: CampaignAccess,
  ) {}

  async exportar(
    user: AccessTokenClaims,
    campaignId: string,
    opciones: { formato: FormatoDeExportacion; disposicion?: DisposicionDelPdf },
  ): Promise<FicheroExportado> {
    const cuaderno = await this.construir(user, campaignId);

    switch (opciones.formato) {
      case 'json':
        return {
          bytes: aJson(cuaderno),
          mediaType: 'application/json; charset=utf-8',
          filename: nombreDelFichero(cuaderno, 'json'),
        };
      case 'csv':
        return {
          bytes: aCsv(cuaderno),
          mediaType: 'text/csv; charset=utf-8',
          filename: nombreDelFichero(cuaderno, 'csv'),
        };
      default: {
        const disposicion = opciones.disposicion ?? 'informe';
        return {
          bytes: await aPdf(cuaderno, disposicion),
          mediaType: 'application/pdf',
          filename: nombreDelFichero(cuaderno, disposicion === 'cue' ? 'cue.pdf' : 'pdf'),
        };
      }
    }
  }

  private async construir(user: AccessTokenClaims, campaignId: string): Promise<CuadernoExportado> {
    const campana = await this.acceso.cargar(user, campaignId);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const [completa, actividades, organizacion, finca, instantanea] = await Promise.all([
        tx.campaign.findUniqueOrThrow({ where: { id: campaignId }, include: INCLUDE_CAMPANA }),
        tx.campaignActivity.findMany({
          where: { campaignId, deletedAt: null },
          include: INCLUDE_ACTIVIDAD,
        }),
        tx.organization.findUnique({ where: { id: organizationId }, select: { name: true } }),
        tx.installation.findUniqueOrThrow({
          where: { id: campana.installationId },
          select: {
            name: true,
            holderName: true,
            holderNif: true,
            reaCode: true,
            address: true,
            regionCode: true,
          },
        }),
        // La última, si se cerró y se reabrió más de una vez.
        tx.campaignSnapshot.findFirst({
          where: { campaignId },
          orderBy: { createdAt: 'desc' },
          select: { content: true },
        }),
      ]);

      const cerrada = campana.status === 'closed' || campana.status === 'archived';
      const pendiente = await revisar(tx, campaignId);

      return construirExportado({
        campana: presentarDetalle(completa),
        actividades,
        organizacion: { name: organizacion?.name ?? null },
        finca,
        instantanea: cerrada && instantanea ? (instantanea.content as CabeceraDeInstantanea) : null,
        pendiente: pendiente.applicable ? pendiente : null,
      });
    });
  }
}
