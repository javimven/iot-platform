import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Campaign, Prisma } from '@prisma/client';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ActividadCompleta, INCLUDE_ACTIVIDAD, presentarActividad } from './activity.presenter';
import {
  DETALLE_DEL_TIPO,
  Destino,
  ParcelaDeCampana,
  comprobarDetalle,
  comprobarQueNoEsFuturo,
  kilosCosechados,
  nutrienteKgHa,
  resolverDestinos,
  superficieDe,
  volumenM3,
} from './activity.rules';
import { CampaignAccess } from './campaign-access';
import {
  ActivityCreateDto,
  ActivityListQueryDto,
  ActivityUpdateDto,
  FertilizationDetailDto,
  FieldWorkDetailDto,
  HarvestDetailDto,
  IrrigationDetailDto,
  PhytosanitaryDetailDto,
  TipoDeActividad,
} from './dto/activity.dto';
import { escribirFecha, leerFecha } from './fechas';

/** Actividades que se enseñan de una vez en la línea de tiempo, si no se pide otra cosa. */
const LIMITE_POR_DEFECTO = 200;

type CamposDeDetalle = Pick<
  ActivityCreateDto,
  'irrigation' | 'fertilization' | 'phytosanitary' | 'harvest' | 'fieldWork'
>;

/**
 * Actividades de una campaña: lo que se ha hecho, que es de lo que se
 * construye el cuaderno (ADR-0012). Registrar va con `campaigns.record`, que
 * tiene también el Operador.
 */
@Injectable()
export class ActivitiesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly acceso: CampaignAccess,
  ) {}

  /** La línea de tiempo: de lo más reciente hacia atrás. */
  async list(user: AccessTokenClaims, campaignId: string, filtros: ActivityListQueryDto) {
    await this.acceso.cargar(user, campaignId);
    const { tenantContext } = resolveOrgContext(user);
    const desde = filtros.from ? leerFecha(filtros.from) : undefined;
    const hasta = filtros.to ? leerFecha(filtros.to) : undefined;

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const actividades = await tx.campaignActivity.findMany({
        where: {
          campaignId,
          deletedAt: null,
          ...(filtros.type ? { type: filtros.type } : {}),
          // Las que tocan el intervalo: una fertirrigación de una quincena
          // sale si el intervalo pedido pisa algún día de esa quincena.
          ...(hasta ? { startDate: { lte: hasta } } : {}),
          ...(desde ? { endDate: { gte: desde } } : {}),
        },
        include: INCLUDE_ACTIVIDAD,
        orderBy: [{ startDate: 'desc' }, { createdAt: 'desc' }],
        take: filtros.limit ?? LIMITE_POR_DEFECTO,
      });
      return actividades.map(presentarActividad);
    });
  }

  async findOne(user: AccessTokenClaims, campaignId: string, activityId: string) {
    await this.acceso.cargar(user, campaignId);
    const { tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, async (tx) =>
      presentarActividad(await actividadViva(tx, campaignId, activityId)),
    );
  }

  async create(user: AccessTokenClaims, campaignId: string, dto: ActivityCreateDto) {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    comprobarDetalle(dto.type, dto, 'alta');
    const inicio = leerFecha(dto.startDate);
    const fin = dto.endDate ? leerFecha(dto.endDate) : inicio;
    comprobarFechas(campana, inicio, fin);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const destinos = resolverDestinos(dto.targets, await parcelasDeLaCampana(tx, campaignId));
      const superficie = superficieDe(destinos);
      if (dto.repeatedFromId) {
        await comprobarQueEsDeLaCampana(tx, campaignId, dto.repeatedFromId);
      }
      const detalle = await detalleParaGuardar(tx, dto.type, dto, superficie, organizationId);

      const creada = await tx.campaignActivity.create({
        data: {
          organizationId,
          campaignId,
          type: dto.type,
          startDate: inicio,
          endDate: fin,
          startTime: dto.startTime ?? null,
          notes: dto.notes?.trim() || null,
          origin: dto.repeatedFromId ? 'repeated' : 'manual',
          repeatedFromId: dto.repeatedFromId ?? null,
          createdBy: user.sub,
          targets: { create: destinosParaGuardar(destinos, organizationId) },
          ...detalle.relaciones,
        },
        include: INCLUDE_ACTIVIDAD,
      });

      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaign_activities.create',
        targetType: 'campaign_activity',
        targetId: creada.id,
        metadata: {
          campaignId,
          type: dto.type,
          startDate: dto.startDate,
          areaHa: superficie,
          parcels: destinos.length,
          origin: creada.origin,
        },
      });
      return presentarActividad(creada);
    });
  }

  /**
   * Cambios. El tipo no cambia; el detalle y los destinos, si vienen,
   * sustituyen a los anteriores enteros. Lo que había antes queda en la
   * auditoría: corregir un tratamiento o una cosecha deja rastro.
   */
  async update(
    user: AccessTokenClaims,
    campaignId: string,
    activityId: string,
    dto: ActivityUpdateDto,
  ) {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const actual = await actividadViva(tx, campaignId, activityId);
      const tipo = actual.type as TipoDeActividad;
      comprobarDetalle(tipo, dto, 'cambio');

      const inicio = dto.startDate ? leerFecha(dto.startDate) : actual.startDate;
      // Una actividad de un día que cambia de día sigue siendo de un día.
      const eraDeUnDia = actual.startDate.getTime() === actual.endDate.getTime();
      const fin = dto.endDate
        ? leerFecha(dto.endDate)
        : dto.startDate && eraDeUnDia
          ? inicio
          : actual.endDate;
      comprobarFechas(campana, inicio, fin);

      const antes = presentarActividad(actual);
      const destinos = dto.targets
        ? resolverDestinos(dto.targets, await parcelasDeLaCampana(tx, campaignId))
        : undefined;
      const superficie = destinos ? superficieDe(destinos) : antes.areaHa;

      await tx.campaignActivity.update({
        where: { id: activityId },
        data: {
          startDate: inicio,
          endDate: fin,
          startTime: dto.startTime,
          notes: dto.notes === undefined ? undefined : dto.notes?.trim() || null,
          updatedBy: user.sub,
        },
      });

      if (destinos) {
        await tx.activityTarget.deleteMany({ where: { activityId } });
        await tx.activityTarget.createMany({
          data: destinosParaGuardar(destinos, organizationId).map((d) => ({ ...d, activityId })),
        });
      }

      const clave = DETALLE_DEL_TIPO[tipo];
      if (clave && dto[clave] !== undefined) {
        await sustituirDetalle(tx, tipo, dto, superficie, organizationId, activityId);
      } else if (destinos) {
        // Cambió la superficie: los normalizados que dependen de ella
        // (m³ de un riego en m³/ha, kg de N/ha de un abonado en kg totales).
        await recalcularNormalizados(tx, actual, superficie);
      }

      const despues = await actividadViva(tx, campaignId, activityId);
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaign_activities.update',
        targetType: 'campaign_activity',
        targetId: activityId,
        metadata: { campaignId, type: tipo, campos: Object.keys(dto), antes },
      });
      return presentarActividad(despues);
    });
  }

  /**
   * Borrado lógico, con quién y por qué. La actividad deja de contar en el
   * cuaderno, pero no desaparece: queda en la base y, entera, en la auditoría.
   */
  async remove(
    user: AccessTokenClaims,
    campaignId: string,
    activityId: string,
    motivo?: string,
  ): Promise<void> {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const actual = await actividadViva(tx, campaignId, activityId);
      await tx.campaignActivity.update({
        where: { id: activityId },
        data: {
          deletedAt: new Date(),
          deletedBy: user.sub,
          deleteReason: motivo?.trim() || null,
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'campaign_activities.delete',
        targetType: 'campaign_activity',
        targetId: activityId,
        metadata: {
          campaignId,
          type: actual.type,
          reason: motivo?.trim() || null,
          antes: presentarActividad(actual),
        },
      });
    });
  }
}

async function actividadViva(
  tx: Prisma.TransactionClient,
  campaignId: string,
  activityId: string,
): Promise<ActividadCompleta> {
  const actividad = await tx.campaignActivity.findFirst({
    where: { id: activityId, campaignId, deletedAt: null },
    include: INCLUDE_ACTIVIDAD,
  });
  if (!actividad) {
    throw new NotFoundException('Activity not found');
  }
  return actividad;
}

/**
 * Fechas coherentes: el fin no antes del inicio, nada antes de que empiece la
 * campaña y nada que todavía no haya pasado. El fin sí puede ser futuro: una
 * fertirrigación de la quincena se puede apuntar el primer día.
 */
function comprobarFechas(campana: Pick<Campaign, 'startDate'>, inicio: Date, fin: Date): void {
  if (fin < inicio) {
    throw new BadRequestException('La fecha de fin es anterior a la de inicio.');
  }
  if (inicio < campana.startDate) {
    const [anyo, mes, dia] = escribirFecha(campana.startDate).split('-');
    throw new BadRequestException(
      `Es anterior al inicio de la campaña (${dia}/${mes}/${anyo}): cambia la fecha de inicio de la campaña si hace falta.`,
    );
  }
  comprobarQueNoEsFuturo(inicio);
}

/** Las parcelas vivas de las unidades vivas de la campaña, con lo que ocupan en cada una. */
async function parcelasDeLaCampana(
  tx: Prisma.TransactionClient,
  campaignId: string,
): Promise<ParcelaDeCampana[]> {
  const unidades = await tx.cropUnit.findMany({
    where: { campaignId, deletedAt: null },
    include: {
      parcels: {
        where: { parcel: { deletedAt: null } },
        include: { parcel: { select: { name: true, areaM2: true } } },
      },
    },
  });
  return unidades.flatMap((u) =>
    u.parcels.map((p) => ({
      cropUnitId: u.id,
      parcelId: p.parcelId,
      parcelName: p.parcel.name,
      cropName: u.cropName,
      areaHa: p.areaHa ?? p.parcel.areaM2 / 10000,
    })),
  );
}

async function comprobarQueEsDeLaCampana(
  tx: Prisma.TransactionClient,
  campaignId: string,
  activityId: string,
): Promise<void> {
  const original = await tx.campaignActivity.findFirst({
    where: { id: activityId, campaignId, deletedAt: null },
    select: { id: true },
  });
  if (!original) {
    throw new BadRequestException('La actividad que se repite no es de esta campaña.');
  }
}

function destinosParaGuardar(destinos: Destino[], organizationId: string) {
  return destinos.map((d) => ({
    cropUnitId: d.cropUnitId,
    parcelId: d.parcelId,
    organizationId,
    areaHa: d.areaHa,
  }));
}

/**
 * Copias de catálogo en el momento de registrar (ADR-0012): si mañana cambia
 * la ficha del aplicador o del equipo, este tratamiento sigue diciendo quién
 * y con qué lo hizo.
 */
async function fotoDePersona(
  tx: Prisma.TransactionClient,
  id: string,
  organizationId: string,
): Promise<Prisma.InputJsonObject> {
  const persona = await tx.notebookPerson.findFirst({
    where: { id, organizationId, deletedAt: null },
  });
  if (!persona) {
    throw new BadRequestException('La persona elegida no está en el cuaderno.');
  }
  return {
    id: persona.id,
    kind: persona.kind,
    firstName: persona.firstName,
    surname1: persona.surname1,
    surname2: persona.surname2,
    companyName: persona.companyName,
    nif: persona.nif,
    ropoNumber: persona.ropoNumber,
    ropoCardType: persona.ropoCardType,
  };
}

async function fotoDeEquipo(
  tx: Prisma.TransactionClient,
  id: string,
  organizationId: string,
): Promise<Prisma.InputJsonObject> {
  const equipo = await tx.notebookEquipment.findFirst({
    where: { id, organizationId, deletedAt: null },
  });
  if (!equipo) {
    throw new BadRequestException('El equipo elegido no está en el cuaderno.');
  }
  return {
    id: equipo.id,
    description: equipo.description,
    brand: equipo.brand,
    model: equipo.model,
    romaNumber: equipo.romaNumber,
    lastInspectionOn: equipo.lastInspectionOn ? escribirFecha(equipo.lastInspectionOn) : null,
  };
}

function datosDeRiego(d: IrrigationDetailDto, superficieHa: number, organizationId: string) {
  return {
    organizationId,
    system: d.system ?? null,
    amount: d.amount ?? null,
    amountUnit: d.amountUnit ?? null,
    volumeM3: volumenM3(d.amount, d.amountUnit, superficieHa),
    waterSource: d.waterSource?.trim() || null,
    meterNumber: d.meterNumber?.trim() || null,
    nitrateMgL: d.nitrateMgL ?? null,
    p2o5MgL: d.p2o5MgL ?? null,
  };
}

async function datosDeAbonado(
  tx: Prisma.TransactionClient,
  d: FertilizationDetailDto,
  superficieHa: number,
  organizationId: string,
) {
  return {
    organizationId,
    fertilizationType: d.fertilizationType ?? null,
    materialType: d.materialType ?? null,
    productName: d.productName?.trim() || null,
    dose: d.dose ?? null,
    doseUnit: d.doseUnit ?? null,
    applicationMethod: d.applicationMethod ?? null,
    nPct: d.nPct ?? null,
    p2o5Pct: d.p2o5Pct ?? null,
    k2oPct: d.k2oPct ?? null,
    organicMatterPct: d.organicMatterPct ?? null,
    nKgHa: nutrienteKgHa(d.dose, d.doseUnit, d.nPct, superficieHa),
    p2o5KgHa: nutrienteKgHa(d.dose, d.doseUnit, d.p2o5Pct, superficieHa),
    k2oKgHa: nutrienteKgHa(d.dose, d.doseUnit, d.k2oPct, superficieHa),
    supplierName: d.supplierName?.trim() || null,
    supplierNif: d.supplierNif?.trim() || null,
    supplierRega: d.supplierRega?.trim() || null,
    supplierNima: d.supplierNima?.trim() || null,
    applicatorCompany: d.applicatorCompany?.trim() || null,
    regferCode: d.regferCode?.trim() || null,
    equipmentId: d.equipmentId ?? null,
    equipmentSnapshot: d.equipmentId
      ? await fotoDeEquipo(tx, d.equipmentId, organizationId)
      : undefined,
  };
}

async function datosDeTratamiento(
  tx: Prisma.TransactionClient,
  d: PhytosanitaryDetailDto,
  organizationId: string,
) {
  return {
    organizationId,
    problem: d.problem?.trim() || null,
    problemCategory: d.problemCategory ?? null,
    justification: d.justification?.trim() || null,
    bbchCode: d.bbchCode ?? null,
    phenologicalStageLabel: d.phenologicalStageLabel?.trim() || null,
    applicatorId: d.applicatorId ?? null,
    applicatorSnapshot: d.applicatorId
      ? await fotoDePersona(tx, d.applicatorId, organizationId)
      : undefined,
    adviserId: d.adviserId ?? null,
    adviserSnapshot: d.adviserId ? await fotoDePersona(tx, d.adviserId, organizationId) : undefined,
    equipmentId: d.equipmentId ?? null,
    equipmentSnapshot: d.equipmentId
      ? await fotoDeEquipo(tx, d.equipmentId, organizationId)
      : undefined,
    manualApplication: d.manualApplication ?? null,
    efficacy: d.efficacy ?? null,
  };
}

function productosDelTratamiento(d: PhytosanitaryDetailDto, organizationId: string) {
  return d.products.map((p, posicion) => ({
    organizationId,
    position: posicion,
    productName: p.productName.trim(),
    registryNumber: p.registryNumber?.trim() || null,
    activeSubstances: p.activeSubstances?.trim() || null,
    dose: p.dose ?? null,
    doseUnit: p.doseUnit ?? null,
    totalQuantity: p.totalQuantity ?? null,
    totalQuantityUnit: p.totalQuantityUnit ?? null,
  }));
}

function datosDeCosecha(d: HarvestDetailDto, organizationId: string) {
  return {
    organizationId,
    product: d.product?.trim() || null,
    quantity: d.quantity ?? null,
    quantityUnit: d.quantityUnit ?? null,
    quantityKg: kilosCosechados(d.quantity, d.quantityUnit),
    lotCode: d.lotCode?.trim() || null,
    deliveryNote: d.deliveryNote?.trim() || null,
    customerName: d.customerName?.trim() || null,
    customerNif: d.customerNif?.trim() || null,
    customerAddress: d.customerAddress?.trim() || null,
    customerRgseaa: d.customerRgseaa?.trim() || null,
    destination: d.destination?.trim() || null,
    qualityGrade: d.qualityGrade?.trim() || null,
  };
}

function datosDeLabor(d: FieldWorkDetailDto, organizationId: string) {
  return {
    organizationId,
    workType: d.workType,
    pruningResiduesLeft: d.pruningResiduesLeft ?? null,
    clearingResiduesLeft: d.clearingResiduesLeft ?? null,
    hours: d.hours ?? null,
    machinery: d.machinery?.trim() || null,
  };
}

/** El detalle del alta, como relaciones anidadas de la actividad. */
async function detalleParaGuardar(
  tx: Prisma.TransactionClient,
  tipo: TipoDeActividad,
  datos: CamposDeDetalle,
  superficieHa: number,
  organizationId: string,
): Promise<{ relaciones: Partial<Prisma.CampaignActivityUncheckedCreateInput> }> {
  switch (tipo) {
    case 'irrigation':
      return {
        relaciones: datos.irrigation
          ? { irrigation: { create: datosDeRiego(datos.irrigation, superficieHa, organizationId) } }
          : {},
      };
    case 'fertilization':
      return {
        relaciones: datos.fertilization
          ? {
              fertilization: {
                create: await datosDeAbonado(tx, datos.fertilization, superficieHa, organizationId),
              },
            }
          : {},
      };
    case 'phytosanitary':
      return {
        relaciones: datos.phytosanitary
          ? {
              phytosanitary: {
                create: await datosDeTratamiento(tx, datos.phytosanitary, organizationId),
              },
              phytosanitaryProducts: {
                create: productosDelTratamiento(datos.phytosanitary, organizationId),
              },
            }
          : {},
      };
    case 'harvest':
      return {
        relaciones: datos.harvest
          ? { harvest: { create: datosDeCosecha(datos.harvest, organizationId) } }
          : {},
      };
    case 'field_work':
      return {
        relaciones: datos.fieldWork
          ? { fieldWork: { create: datosDeLabor(datos.fieldWork, organizationId) } }
          : {},
      };
    default:
      return { relaciones: {} };
  }
}

/** El detalle de un cambio sustituye al anterior entero. */
async function sustituirDetalle(
  tx: Prisma.TransactionClient,
  tipo: TipoDeActividad,
  datos: CamposDeDetalle,
  superficieHa: number,
  organizationId: string,
  activityId: string,
): Promise<void> {
  switch (tipo) {
    case 'irrigation':
      await tx.irrigationDetail.deleteMany({ where: { activityId } });
      await tx.irrigationDetail.create({
        data: { activityId, ...datosDeRiego(datos.irrigation!, superficieHa, organizationId) },
      });
      return;
    case 'fertilization':
      await tx.fertilizationDetail.deleteMany({ where: { activityId } });
      await tx.fertilizationDetail.create({
        data: {
          activityId,
          ...(await datosDeAbonado(tx, datos.fertilization!, superficieHa, organizationId)),
        },
      });
      return;
    case 'phytosanitary':
      await tx.phytosanitaryProduct.deleteMany({ where: { activityId } });
      await tx.phytosanitaryDetail.deleteMany({ where: { activityId } });
      await tx.phytosanitaryDetail.create({
        data: {
          activityId,
          ...(await datosDeTratamiento(tx, datos.phytosanitary!, organizationId)),
        },
      });
      await tx.phytosanitaryProduct.createMany({
        data: productosDelTratamiento(datos.phytosanitary!, organizationId).map((p) => ({
          ...p,
          activityId,
        })),
      });
      return;
    case 'harvest':
      await tx.harvestDetail.deleteMany({ where: { activityId } });
      await tx.harvestDetail.create({
        data: { activityId, ...datosDeCosecha(datos.harvest!, organizationId) },
      });
      return;
    case 'field_work':
      await tx.fieldWorkDetail.deleteMany({ where: { activityId } });
      await tx.fieldWorkDetail.create({
        data: { activityId, ...datosDeLabor(datos.fieldWork!, organizationId) },
      });
      return;
    default:
      return;
  }
}

async function recalcularNormalizados(
  tx: Prisma.TransactionClient,
  actual: ActividadCompleta,
  superficieHa: number,
): Promise<void> {
  if (actual.irrigation) {
    await tx.irrigationDetail.update({
      where: { activityId: actual.id },
      data: {
        volumeM3: volumenM3(actual.irrigation.amount, actual.irrigation.amountUnit, superficieHa),
      },
    });
  }
  if (actual.fertilization) {
    const f = actual.fertilization;
    await tx.fertilizationDetail.update({
      where: { activityId: actual.id },
      data: {
        nKgHa: nutrienteKgHa(f.dose, f.doseUnit, f.nPct, superficieHa),
        p2o5KgHa: nutrienteKgHa(f.dose, f.doseUnit, f.p2o5Pct, superficieHa),
        k2oKgHa: nutrienteKgHa(f.dose, f.doseUnit, f.k2oPct, superficieHa),
      },
    });
  }
}
