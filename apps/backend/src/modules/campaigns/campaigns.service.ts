import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { scopeWhereClause } from '../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CampaignAccess } from './campaign-access';
import {
  CampanaCompleta,
  INCLUDE_CAMPANA,
  UltimaActividad,
  hectareas,
  nombreAutomatico,
  presentarDetalle,
  presentarEnLista,
} from './campaign.presenter';
import {
  comprobarParcelasSinRepetir,
  comprobarSuperficies,
  cultivosDelCatalogo,
  datosDeUnidad,
  parcelasParaGuardar,
} from './crop-unit.rules';
import {
  CampaignCloseDto,
  CampaignCreateDto,
  CampaignListQueryDto,
  CampaignReopenDto,
  CampaignUpdateDto,
  CampaignUpgradeDto,
} from './dto/campaign.dto';
import { escribirFecha, escribirFechaONulo, leerFecha } from './fechas';
import { perfilParaGuardar } from './notebook-profile';

/** Versión del formato de la instantánea de cierre (`campaign_snapshots.content_version`). */
const VERSION_INSTANTANEA = 1;

/**
 * Campañas (BACKLOG.md #60, ADR-0012/0013). Mismo esqueleto que parcelas:
 * contexto de organización, alcance por finca y auditoría dentro de la misma
 * transacción que la acción.
 */
@Injectable()
export class CampaignsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly acceso: CampaignAccess,
  ) {}

  async list(user: AccessTokenClaims, filtros: CampaignListQueryDto) {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const alcance = await this.acceso.alcance(user);
    if (filtros.installationId && alcance !== 'all' && !alcance.includes(filtros.installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }

    const where: Prisma.CampaignWhereInput = {
      organizationId,
      deletedAt: null,
      ...scopeWhereClause(alcance),
      ...(filtros.installationId ? { installationId: filtros.installationId } : {}),
      ...(filtros.status ? { status: filtros.status } : {}),
      ...(filtros.cropId
        ? { cropUnits: { some: { cropId: filtros.cropId, deletedAt: null } } }
        : {}),
      ...(filtros.year ? enElAnyo(filtros.year) : {}),
    };

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const campanas = await tx.campaign.findMany({
        where,
        include: INCLUDE_CAMPANA,
        orderBy: [{ startDate: 'desc' }, { createdAt: 'desc' }],
      });
      const ultimas = await ultimasActividades(
        tx,
        campanas.map((c) => c.id),
      );
      return campanas.map((c) => presentarEnLista(c, ultimas.get(c.id)));
    });
  }

  async create(user: AccessTokenClaims, installationId: string, dto: CampaignCreateDto) {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    await this.acceso.asegurarFincaEnAlcance(user, installationId);

    const inicio = leerFecha(dto.startDate);
    const finPrevista = dto.expectedEndDate ? leerFecha(dto.expectedEndDate) : undefined;
    comprobarOrdenDeFechas(inicio, finPrevista ?? null);
    if (dto.managementMode === 'simple' && dto.notebookProfile) {
      throw new BadRequestException('El perfil del cuaderno solo se usa en el modo completo.');
    }
    dto.cropUnits.forEach((u) => comprobarParcelasSinRepetir(u.parcels));

    const campana = await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const finca = await tx.installation.findFirst({
        where: { id: installationId, organizationId, deletedAt: null },
        select: { id: true },
      });
      if (!finca) {
        throw new NotFoundException('Installation not found');
      }

      const parcelas = await this.acceso.parcelasDeLaFinca(
        tx,
        installationId,
        dto.cropUnits.flatMap((u) => u.parcels.map((p) => p.parcelId)),
      );
      dto.cropUnits.forEach((u) => comprobarSuperficies(u.parcels, parcelas));
      const cultivos = await cultivosDelCatalogo(
        tx,
        dto.cropUnits.map((u) => u.cropId),
      );
      const unidades = dto.cropUnits.map((u) => ({
        ...datosDeUnidad(u, cultivos, organizationId),
        parcels: { create: parcelasParaGuardar(u.parcels, organizationId) },
      }));

      const creada = await tx.campaign.create({
        data: {
          organizationId,
          installationId,
          name:
            dto.name?.trim() ||
            nombreAutomatico(
              unidades[0].cropName,
              unidades[0].variety ?? undefined,
              inicio,
              finPrevista,
            ),
          managementMode: dto.managementMode,
          startDate: inicio,
          expectedEndDate: finPrevista ?? null,
          notes: dto.notes ?? null,
          notebookProfile:
            dto.managementMode === 'complete'
              ? (perfilParaGuardar(dto.notebookProfile) as Prisma.InputJsonObject)
              : {},
          createdBy: user.sub,
          cropUnits: { create: unidades },
        },
        include: INCLUDE_CAMPANA,
      });

      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.create',
        targetType: 'campaign',
        targetId: creada.id,
        metadata: {
          name: creada.name,
          installationId,
          managementMode: creada.managementMode,
          cropUnits: creada.cropUnits.length,
        },
      });
      return creada;
    });

    return presentarDetalle(campana);
  }

  async findOne(user: AccessTokenClaims, id: string) {
    await this.acceso.cargar(user, id);
    const { tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const campana = await tx.campaign.findUniqueOrThrow({
        where: { id },
        include: INCLUDE_CAMPANA,
      });
      const ultimas = await ultimasActividades(tx, [id]);
      return presentarDetalle(campana, ultimas.get(id));
    });
  }

  async update(user: AccessTokenClaims, id: string, dto: CampaignUpdateDto) {
    const actual = await this.acceso.cargar(user, id);
    this.acceso.asegurarAbierta(actual);
    if (dto.notebookProfile && actual.managementMode !== 'complete') {
      throw new BadRequestException('El perfil del cuaderno solo se usa en el modo completo.');
    }

    const inicio = dto.startDate ? leerFecha(dto.startDate) : actual.startDate;
    const finPrevista =
      dto.expectedEndDate === undefined
        ? actual.expectedEndDate
        : dto.expectedEndDate === null
          ? null
          : leerFecha(dto.expectedEndDate);
    comprobarOrdenDeFechas(inicio, finPrevista);
    const nombre = dto.name?.trim();
    if (dto.name !== undefined && !nombre) {
      throw new BadRequestException('El nombre de la campaña no puede quedar vacío.');
    }

    return this.enTransaccion(user, id, async (tx, organizationId) => {
      if (dto.startDate) {
        // La campaña no puede empezar después de lo que ya se ha hecho en ella.
        const primera = await tx.campaignActivity.findFirst({
          where: { campaignId: id, deletedAt: null },
          orderBy: { startDate: 'asc' },
          select: { startDate: true },
        });
        if (primera && primera.startDate < inicio) {
          const [anyo, mes, dia] = escribirFecha(primera.startDate).split('-');
          throw new ConflictException(
            `Hay actividades registradas desde el ${dia}/${mes}/${anyo}: la campaña no puede empezar después.`,
          );
        }
      }
      const campana = await tx.campaign.update({
        where: { id },
        data: {
          name: nombre,
          startDate: dto.startDate ? inicio : undefined,
          expectedEndDate: dto.expectedEndDate === undefined ? undefined : finPrevista,
          notes: dto.notes,
          notebookProfile: dto.notebookProfile
            ? (perfilParaGuardar(dto.notebookProfile) as Prisma.InputJsonObject)
            : undefined,
        },
        include: INCLUDE_CAMPANA,
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.update',
        targetType: 'campaign',
        targetId: id,
        metadata: { name: campana.name, campos: Object.keys(dto) },
      });
      return campana;
    });
  }

  /**
   * "Completar cuaderno de campo" (ADR-0013): la misma campaña pasa a modo
   * completo. No se copia ni se borra nada; las actividades ya registradas
   * siguen siendo la base.
   */
  async upgrade(user: AccessTokenClaims, id: string, dto: CampaignUpgradeDto) {
    const actual = await this.acceso.cargar(user, id);
    this.acceso.asegurarAbierta(actual);
    if (actual.managementMode === 'complete') {
      throw new ConflictException('La campaña ya es un cuaderno completo.');
    }

    return this.enTransaccion(user, id, async (tx, organizationId) => {
      const campana = await tx.campaign.update({
        where: { id },
        data: {
          managementMode: 'complete',
          notebookProfile: perfilParaGuardar(dto.notebookProfile) as Prisma.InputJsonObject,
        },
        include: INCLUDE_CAMPANA,
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.upgrade',
        targetType: 'campaign',
        targetId: id,
        metadata: { name: campana.name, de: 'simple', a: 'complete' },
      });
      return campana;
    });
  }

  /**
   * Cerrar: la campaña queda con su fecha de fin y su cuaderno congelado, y se
   * guarda una instantánea de cómo era todo lo que no es de la campaña pero la
   * describe (titular, finca, parcelas). Si mañana cambian, el cuaderno
   * cerrado no (ADR-0012).
   *
   * La revisión de lo pendiente del cuaderno completo llega con la fase 5.
   */
  async close(user: AccessTokenClaims, id: string, dto: CampaignCloseDto) {
    const actual = await this.acceso.cargar(user, id);
    if (actual.status === 'closed' || actual.status === 'archived') {
      throw new ConflictException('La campaña ya está cerrada.');
    }
    const fin = leerFecha(dto.endDate);
    if (fin < actual.startDate) {
      throw new BadRequestException('La fecha de fin es anterior al inicio de la campaña.');
    }

    return this.enTransaccion(user, id, async (tx, organizationId) => {
      const campana = await tx.campaign.update({
        where: { id },
        data: {
          status: 'closed',
          endDate: fin,
          declaredProductionKg: dto.declaredProductionKg ?? null,
          closingNotes: dto.closingNotes ?? null,
          closedAt: new Date(),
          closedBy: user.sub,
        },
        include: INCLUDE_CAMPANA,
      });
      const instantanea = await tx.campaignSnapshot.create({
        data: {
          organizationId,
          campaignId: id,
          reason: 'close',
          content: await contenidoDeInstantanea(tx, campana, organizationId),
          contentVersion: VERSION_INSTANTANEA,
          createdBy: user.sub,
        },
        select: { id: true },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.close',
        targetType: 'campaign',
        targetId: id,
        metadata: {
          name: campana.name,
          endDate: dto.endDate,
          snapshotId: instantanea.id,
        },
      });
      return campana;
    });
  }

  /** Reabrir es corregir un cuaderno cerrado: con motivo, y auditado. */
  async reopen(user: AccessTokenClaims, id: string, dto: CampaignReopenDto) {
    const actual = await this.acceso.cargar(user, id);
    if (actual.status !== 'closed') {
      throw new ConflictException('Solo se puede reabrir una campaña cerrada.');
    }

    return this.enTransaccion(user, id, async (tx, organizationId) => {
      const campana = await tx.campaign.update({
        where: { id },
        data: { status: 'active', closedAt: null, closedBy: null },
        include: INCLUDE_CAMPANA,
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.reopen',
        targetType: 'campaign',
        targetId: id,
        metadata: { name: campana.name, reason: dto.reason.trim() },
      });
      return campana;
    });
  }

  /**
   * Borrado lógico. Una campaña cerrada no se borra: su cuaderno es historia,
   * y borrarlo sin más sería justo lo que el cierre intenta evitar.
   */
  async softDelete(user: AccessTokenClaims, id: string): Promise<void> {
    const actual = await this.acceso.cargar(user, id);
    if (actual.status === 'closed' || actual.status === 'archived') {
      throw new ConflictException(
        'Una campaña cerrada no se borra: su cuaderno es historia. Reábrela primero si de verdad hay que borrarla.',
      );
    }
    const { organizationId, tenantContext } = resolveOrgContext(user);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.campaign.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaigns.delete',
        targetType: 'campaign',
        targetId: id,
        metadata: { name: actual.name },
      });
    });
  }

  /** Transacción de una acción sobre la campaña, que devuelve su ficha. */
  private async enTransaccion(
    user: AccessTokenClaims,
    id: string,
    accion: (tx: Prisma.TransactionClient, organizationId: string) => Promise<CampanaCompleta>,
  ) {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const campana = await accion(tx, organizationId);
      const ultimas = await ultimasActividades(tx, [id]);
      return presentarDetalle(campana, ultimas.get(id));
    });
  }
}

function comprobarOrdenDeFechas(inicio: Date, finPrevista: Date | null): void {
  if (finPrevista && finPrevista < inicio) {
    throw new BadRequestException('La fecha prevista de fin es anterior al inicio.');
  }
}

/**
 * Campañas que tocan ese año: empiezan antes de que acabe, y no acabaron
 * antes de que empiece. Una sin cerrar sigue en curso, sea cual sea su fecha
 * prevista.
 */
function enElAnyo(anyo: number): Prisma.CampaignWhereInput {
  return {
    AND: [
      { startDate: { lte: new Date(Date.UTC(anyo, 11, 31)) } },
      { OR: [{ endDate: { gte: new Date(Date.UTC(anyo, 0, 1)) } }, { endDate: null }] },
    ],
  };
}

/**
 * La última actividad de cada campaña, para la tarjeta del listado. Una sola
 * consulta con `DISTINCT ON`, en vez de traer todas las actividades de todas
 * las campañas para quedarse con una.
 */
export async function ultimasActividades(
  tx: Prisma.TransactionClient,
  ids: string[],
): Promise<Map<string, UltimaActividad>> {
  if (ids.length === 0) {
    return new Map();
  }
  const filas = await tx.$queryRaw<Array<{ campaign_id: string; type: string; start_date: Date }>>`
    SELECT DISTINCT ON (campaign_id) campaign_id, type, start_date
      FROM campaign_activities
     WHERE campaign_id = ANY(${ids}::uuid[]) AND deleted_at IS NULL
     ORDER BY campaign_id, start_date DESC, created_at DESC
  `;
  return new Map(
    filas.map((f) => [
      f.campaign_id,
      { campaignId: f.campaign_id, type: f.type, startDate: f.start_date },
    ]),
  );
}

/**
 * Lo que se congela al cerrar: lo que no es de la campaña pero la describe.
 * Fechas como texto y superficies ya calculadas: la instantánea tiene que
 * poder leerse igual dentro de años, sin depender de cómo se calculen hoy.
 */
async function contenidoDeInstantanea(
  tx: Prisma.TransactionClient,
  campana: CampanaCompleta,
  organizationId: string,
): Promise<Prisma.InputJsonObject> {
  const [organizacion, finca] = await Promise.all([
    tx.organization.findUnique({ where: { id: organizationId }, select: { name: true } }),
    tx.installation.findUniqueOrThrow({
      where: { id: campana.installationId },
      select: {
        id: true,
        name: true,
        locationText: true,
        latitude: true,
        longitude: true,
        holderName: true,
        holderNif: true,
        reaCode: true,
        address: true,
        regionCode: true,
      },
    }),
  ]);
  const detalle = presentarDetalle(campana);

  return {
    organization: { id: organizationId, name: organizacion?.name ?? null },
    installation: finca,
    campaign: {
      id: campana.id,
      name: campana.name,
      managementMode: campana.managementMode,
      startDate: escribirFecha(campana.startDate),
      expectedEndDate: escribirFechaONulo(campana.expectedEndDate),
      endDate: escribirFechaONulo(campana.endDate),
      declaredProductionKg: campana.declaredProductionKg,
      notebookProfile: campana.notebookProfile as Prisma.InputJsonValue,
    },
    areaHa: hectareas(detalle.areaHa),
    cropUnits: detalle.cropUnits.map((u) => ({
      id: u.id,
      cropId: u.cropId,
      cropName: u.cropName,
      variety: u.variety,
      previousCrop: u.previousCrop,
      waterRegime: u.waterRegime,
      growingEnvironment: u.growingEnvironment,
      productionSystem: u.productionSystem,
      areaHa: u.effectiveAreaHa,
      parcels: u.parcels.map((p) => ({
        parcelId: p.parcelId,
        name: p.name,
        parcelAreaHa: p.parcelAreaHa,
        areaHa: p.effectiveAreaHa,
      })),
    })),
  };
}
