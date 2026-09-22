import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CampaignAccess } from './campaign-access';
import { INCLUDE_CAMPANA, presentarDetalle } from './campaign.presenter';
import { ultimasActividades } from './campaigns.service';
import {
  comprobarParcelasSinRepetir,
  comprobarSuperficies,
  cultivosDelCatalogo,
  datosDeUnidad,
  nombreDelCultivo,
  parcelasParaGuardar,
} from './crop-unit.rules';
import { CropUnitCreateDto, CropUnitUpdateDto } from './dto/crop-unit.dto';

/**
 * Unidades de cultivo de una campaña ya creada (ADR-0012). Toda acción
 * devuelve la ficha completa de la campaña: la superficie total, las parcelas
 * y el nombre de los cultivos cambian con ella, y así la app se refresca de
 * una vez.
 */
@Injectable()
export class CropUnitsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly acceso: CampaignAccess,
  ) {}

  async add(user: AccessTokenClaims, campaignId: string, dto: CropUnitCreateDto) {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    comprobarParcelasSinRepetir(dto.parcels);

    return this.enTransaccion(user, campaignId, async (tx, organizationId) => {
      const parcelas = await this.acceso.parcelasDeLaFinca(
        tx,
        campana.installationId,
        dto.parcels.map((p) => p.parcelId),
      );
      comprobarSuperficies(dto.parcels, parcelas);
      const cultivos = await cultivosDelCatalogo(tx, [dto.cropId]);
      const unidad = await tx.cropUnit.create({
        data: {
          ...datosDeUnidad(dto, cultivos, organizationId),
          campaignId,
          parcels: { create: parcelasParaGuardar(dto.parcels, organizationId) },
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'crop_units.create',
        targetType: 'crop_unit',
        targetId: unidad.id,
        metadata: { campaignId, cropName: unidad.cropName, parcels: dto.parcels.length },
      });
    });
  }

  /**
   * Cambios en una unidad. Si vienen `parcels`, son la lista completa: se
   * añaden las nuevas, se actualiza la superficie de las que siguen y se
   * quitan las que no están, salvo que tengan actividades registradas en la
   * unidad (su historia colgaría de la nada).
   */
  async update(
    user: AccessTokenClaims,
    campaignId: string,
    unitId: string,
    dto: CropUnitUpdateDto,
  ) {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    if (dto.parcels) {
      comprobarParcelasSinRepetir(dto.parcels);
    }

    return this.enTransaccion(user, campaignId, async (tx, organizationId) => {
      const unidad = await this.unidadViva(tx, campaignId, unitId);

      // Cambiar el cultivo del catálogo sin escribir nombre = el nombre del
      // catálogo; escribir un nombre = ese nombre.
      let cropName: string | undefined;
      if (dto.cropId !== undefined || dto.cropName !== undefined) {
        const cropId = dto.cropId ?? unidad.cropId ?? undefined;
        const cultivos = await cultivosDelCatalogo(tx, [cropId]);
        cropName = nombreDelCultivo({ cropId, cropName: dto.cropName }, cultivos);
      }

      await tx.cropUnit.update({
        where: { id: unitId },
        data: {
          cropId: dto.cropId,
          cropName,
          variety: dto.variety === undefined ? undefined : dto.variety.trim() || null,
          previousCrop:
            dto.previousCrop === undefined ? undefined : dto.previousCrop.trim() || null,
          waterRegime: dto.waterRegime,
          growingEnvironment: dto.growingEnvironment,
          productionSystem: dto.productionSystem,
          areaHa: dto.areaHa,
          expectedYieldKgHa: dto.expectedYieldKgHa,
          notes: dto.notes,
        },
      });

      let cambiosDeParcelas: { anadidas: number; quitadas: number } | undefined;
      if (dto.parcels) {
        const parcelas = await this.acceso.parcelasDeLaFinca(
          tx,
          campana.installationId,
          dto.parcels.map((p) => p.parcelId),
        );
        comprobarSuperficies(dto.parcels, parcelas);
        cambiosDeParcelas = await this.sustituirParcelas(
          tx,
          unidad.id,
          unidad.parcels,
          dto.parcels,
          organizationId,
        );
      }

      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'crop_units.update',
        targetType: 'crop_unit',
        targetId: unitId,
        metadata: { campaignId, campos: Object.keys(dto), ...cambiosDeParcelas },
      });
    });
  }

  /**
   * Quitar una unidad (borrado lógico). No si es la única —una campaña sin
   * cultivo no es una campaña— ni si tiene actividades registradas.
   */
  async remove(user: AccessTokenClaims, campaignId: string, unitId: string): Promise<void> {
    const campana = await this.acceso.cargar(user, campaignId);
    this.acceso.asegurarAbierta(campana);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const unidad = await this.unidadViva(tx, campaignId, unitId);
      const otras = await tx.cropUnit.count({
        where: { campaignId, deletedAt: null, id: { not: unitId } },
      });
      if (otras === 0) {
        throw new ConflictException('Una campaña necesita al menos una unidad de cultivo.');
      }
      const conActividades = await tx.activityTarget.count({
        where: { cropUnitId: unitId, activity: { deletedAt: null } },
      });
      if (conActividades > 0) {
        throw new ConflictException(
          'Esta unidad de cultivo tiene actividades registradas: no se puede quitar.',
        );
      }
      await tx.cropUnit.update({ where: { id: unitId }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'crop_units.delete',
        targetType: 'crop_unit',
        targetId: unitId,
        metadata: { campaignId, cropName: unidad.cropName },
      });
    });
  }

  private async unidadViva(tx: Prisma.TransactionClient, campaignId: string, unitId: string) {
    const unidad = await tx.cropUnit.findFirst({
      where: { id: unitId, campaignId, deletedAt: null },
      include: { parcels: { include: { parcel: { select: { name: true } } } } },
    });
    if (!unidad) {
      throw new NotFoundException('Crop unit not found');
    }
    return unidad;
  }

  private async sustituirParcelas(
    tx: Prisma.TransactionClient,
    unitId: string,
    actuales: Array<{ parcelId: string; areaHa: number | null; parcel: { name: string } }>,
    nuevas: Array<{ parcelId: string; areaHa?: number }>,
    organizationId: string,
  ): Promise<{ anadidas: number; quitadas: number }> {
    const quedan = new Set(nuevas.map((p) => p.parcelId));
    const antes = new Map(actuales.map((p) => [p.parcelId, p]));
    const quitar = actuales.filter((p) => !quedan.has(p.parcelId));

    for (const parcela of quitar) {
      // Cualquier destino cuenta, también el de una actividad borrada: la
      // clave foránea de `activity_targets` no dejaría quitarla, y el
      // mensaje tiene que decir por qué.
      const usos = await tx.activityTarget.count({
        where: { cropUnitId: unitId, parcelId: parcela.parcelId },
      });
      if (usos > 0) {
        throw new ConflictException(
          `La parcela "${parcela.parcel.name}" tiene actividades registradas en esta unidad: no se puede quitar.`,
        );
      }
    }
    if (quitar.length > 0) {
      await tx.cropUnitParcel.deleteMany({
        where: { cropUnitId: unitId, parcelId: { in: quitar.map((p) => p.parcelId) } },
      });
    }

    const anadir = nuevas.filter((p) => !antes.has(p.parcelId));
    if (anadir.length > 0) {
      await tx.cropUnitParcel.createMany({
        data: parcelasParaGuardar(anadir, organizationId).map((p) => ({
          ...p,
          cropUnitId: unitId,
        })),
      });
    }

    for (const parcela of nuevas) {
      const previa = antes.get(parcela.parcelId);
      const areaHa = parcela.areaHa ?? null;
      if (previa && previa.areaHa !== areaHa) {
        await tx.cropUnitParcel.update({
          where: { cropUnitId_parcelId: { cropUnitId: unitId, parcelId: parcela.parcelId } },
          data: { areaHa },
        });
      }
    }

    return { anadidas: anadir.length, quitadas: quitar.length };
  }

  private async enTransaccion(
    user: AccessTokenClaims,
    campaignId: string,
    accion: (tx: Prisma.TransactionClient, organizationId: string) => Promise<void>,
  ) {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await accion(tx, organizationId);
      const campana = await tx.campaign.findUniqueOrThrow({
        where: { id: campaignId },
        include: INCLUDE_CAMPANA,
      });
      const ultimas = await ultimasActividades(tx, [campaignId]);
      return presentarDetalle(campana, ultimas.get(campaignId));
    });
  }
}
