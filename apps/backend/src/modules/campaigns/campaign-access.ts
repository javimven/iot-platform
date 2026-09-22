import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Campaign, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import {
  InstallationScope,
  resolveInstallationScope,
} from '../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../common/permissions/org-context';

/**
 * Quién puede tocar qué campaña, en un solo sitio (mismo criterio que
 * `ParcelsService.findOne` para el satélite): la organización la pone la RLS,
 * y el alcance por finca (PERMISSIONS.md §2) se comprueba aquí. Una campaña
 * es de una finca, así que quien solo ve unas fincas solo ve sus campañas.
 */
@Injectable()
export class CampaignAccess {
  constructor(private readonly prisma: PrismaService) {}

  alcance(user: AccessTokenClaims): Promise<InstallationScope> {
    return resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
  }

  async asegurarFincaEnAlcance(user: AccessTokenClaims, installationId: string): Promise<void> {
    const alcance = await this.alcance(user);
    if (alcance !== 'all' && !alcance.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }

  /** La campaña viva, de la organización activa y dentro del alcance; 404 si no. */
  async cargar(user: AccessTokenClaims, campaignId: string): Promise<Campaign> {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const campana = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.campaign.findFirst({ where: { id: campaignId, organizationId, deletedAt: null } }),
    );
    if (!campana) {
      throw new NotFoundException('Campaign not found');
    }
    await this.asegurarFincaEnAlcance(user, campana.installationId);
    return campana;
  }

  /**
   * Una campaña cerrada no se modifica: su cuaderno queda como estaba. Para
   * corregir algo se reabre (y queda auditado). La base lo impide también
   * (trigger `check_campaign_open`, migración 0011); esto da el mensaje claro.
   */
  asegurarAbierta(campana: Pick<Campaign, 'status'>): void {
    if (campana.status === 'closed' || campana.status === 'archived') {
      throw new ConflictException('La campaña está cerrada: reábrela para modificarla.');
    }
  }

  /** Las parcelas vivas de esa finca, con su superficie; 400 si alguna no lo es. */
  async parcelasDeLaFinca(
    tx: Prisma.TransactionClient,
    installationId: string,
    parcelIds: string[],
  ): Promise<Map<string, { id: string; name: string; areaHa: number }>> {
    const unicas = [...new Set(parcelIds)];
    const parcelas = await tx.parcel.findMany({
      where: { id: { in: unicas }, installationId, deletedAt: null },
      select: { id: true, name: true, areaM2: true },
    });
    if (parcelas.length !== unicas.length) {
      throw new BadRequestException('Alguna parcela no existe o no es de la finca de la campaña.');
    }
    return new Map(
      parcelas.map((p) => [p.id, { id: p.id, name: p.name, areaHa: p.areaM2 / 10000 }]),
    );
  }
}
