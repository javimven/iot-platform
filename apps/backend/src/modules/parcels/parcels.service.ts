import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { ParcelCreateDto, ParcelUpdateDto } from './dto/parcel.dto';
import { ParcelGeometryService } from './parcel-geometry.service';
import { ParcelaConGeometria, ParcelsRepository } from './parcels.repository';
import { SatelliteQueueProducer } from '../../common/queues/satellite-queue.producer';

/**
 * Parcelas (BACKLOG.md #36): el recinto real de cultivo del que el modulo de
 * satelite calcula el NDVI. Mismo esqueleto que el resto del Directorio IoT
 * (`ZonesService`): contexto de organizacion, alcance por instalacion y
 * auditoria dentro de la misma transaccion que la accion.
 *
 * Lo que cambia respecto a una zona: la geometria. Se normaliza antes de
 * tocar SQL (`ParcelGeometryService`) y se guarda y se lee a traves de
 * `ParcelsRepository`, porque Prisma no modela tipos de PostGIS (ADR-0009).
 */
@Injectable()
export class ParcelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly geometria: ParcelGeometryService,
    private readonly repositorio: ParcelsRepository,
    private readonly colaSatelite: SatelliteQueueProducer,
  ) {}

  async create(
    user: AccessTokenClaims,
    installationId: string,
    dto: ParcelCreateDto,
  ): Promise<ParcelaConGeometria> {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    await this.assertInstallationInScope(user, installationId);
    const geometry = this.geometria.normalizar(dto.geometry);

    const { parcela, conSatelite } = await this.prisma.runInTenantContext(
      tenantContext,
      async (tx) => {
        await this.assertInstallationExists(tx, installationId, organizationId);
        const parcela = await this.conNombreLibre(installationId, dto.name, () =>
          this.repositorio.crear(tx, {
            organizationId,
            installationId,
            name: dto.name,
            notes: dto.notes ?? null,
            geometry,
          }),
        );
        await this.auditLog.record(tx, {
          organizationId,
          actorUserId: user.sub,
          action: 'parcels.create',
          targetType: 'parcel',
          targetId: parcela.id,
          // Ni rastro de la geometria en la auditoria: son kilobytes de
          // coordenadas que nadie va a leer en una tabla de eventos.
          metadata: { name: parcela.name, installationId, areaM2: Math.round(parcela.areaM2) },
        });
        const conSatelite = await tx.organizationFeature.findFirst({
          where: { organizationId, featureCode: 'satellite_imagery', enabled: true },
          select: { featureCode: true },
        });
        return { parcela, conSatelite: conSatelite !== null };
      },
    );

    // Fuera de la transaccion y sin bloquear la respuesta: si el encolado
    // falla, la parcela ya esta creada y el repaso diario la recogera igual.
    // Sin esto, una parcela recien dibujada no tendria ni un dato hasta la
    // manana siguiente.
    //
    // Solo con el satelite contratado: una parcela dibujada para Campañas no
    // puede gastar cuota de Copernicus.
    if (conSatelite) {
      await this.colaSatelite.encolarHistorico({ organizationId, parcelId: parcela.id });
    }
    return parcela;
  }

  async findAllForInstallation(
    user: AccessTokenClaims,
    installationId: string,
  ): Promise<ParcelaConGeometria[]> {
    const { tenantContext } = resolveOrgContext(user);
    await this.assertInstallationInScope(user, installationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      this.repositorio.porInstalacion(tx, installationId),
    );
  }

  async findOne(user: AccessTokenClaims, id: string): Promise<ParcelaConGeometria> {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const parcela = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      this.repositorio.porId(tx, id, organizationId),
    );
    if (!parcela) {
      throw new NotFoundException('Parcel not found');
    }
    await this.assertInstallationInScope(user, parcela.installationId);
    return parcela;
  }

  async update(
    user: AccessTokenClaims,
    id: string,
    dto: ParcelUpdateDto,
  ): Promise<ParcelaConGeometria> {
    const actual = await this.findOne(user, id);
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const geometry = dto.geometry === undefined ? null : this.geometria.normalizar(dto.geometry);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      if (dto.name !== undefined || dto.notes !== undefined) {
        await this.conNombreLibre(actual.installationId, dto.name ?? actual.name, () =>
          tx.parcel.update({
            where: { id },
            data: { name: dto.name, notes: dto.notes },
          }),
        );
      }
      const parcela = geometry
        ? await this.repositorio.actualizarGeometria(tx, id, geometry)
        : ((await this.repositorio.porId(tx, id, organizationId)) as ParcelaConGeometria);

      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'parcels.update',
        targetType: 'parcel',
        targetId: id,
        metadata: {
          name: parcela.name,
          contornoRedibujado: geometry !== null,
          geometryVersion: parcela.geometryVersion,
        },
      });
      return parcela;
    });
  }

  /**
   * Borrado logico, como el resto del Directorio. Las estaciones que
   * apuntaban a esta parcela se quedan sin parcela (no se borran ni se
   * bloquea el borrado por su culpa): la parcela es una capa de analisis
   * sobre la estacion, no al reves.
   */
  async softDelete(user: AccessTokenClaims, id: string): Promise<void> {
    const parcela = await this.findOne(user, id);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const estaciones = await tx.gateway.updateMany({
        where: { parcelId: id },
        data: { parcelId: null },
      });
      await tx.parcel.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'parcels.delete',
        targetType: 'parcel',
        targetId: id,
        metadata: { name: parcela.name, estacionesDesasignadas: estaciones.count },
      });
    });
  }

  /**
   * El indice unico parcial `parcels_nombre_por_finca_uniq` es quien manda
   * (dos peticiones a la vez no se pisan), pero un P2002 a secas sale como un
   * 500 poco util: se traduce a 409 con el nombre que choca.
   */
  private async conNombreLibre<T>(
    installationId: string,
    name: string,
    operacion: () => Promise<T>,
  ): Promise<T> {
    try {
      return await operacion();
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException(`Ya hay una parcela llamada "${name}" en esta finca.`);
      }
      // El SQL crudo del repositorio no pasa por el mapeo de errores de
      // Prisma: la violacion del indice unico llega como error nativo.
      if (error instanceof Error && error.message.includes('parcels_nombre_por_finca_uniq')) {
        throw new ConflictException(`Ya hay una parcela llamada "${name}" en esta finca.`);
      }
      throw error;
    }
  }

  private async assertInstallationExists(
    tx: Prisma.TransactionClient,
    installationId: string,
    organizationId: string,
  ): Promise<void> {
    const instalacion = await tx.installation.findFirst({
      where: { id: installationId, organizationId, deletedAt: null },
    });
    if (!instalacion) {
      throw new NotFoundException('Installation not found');
    }
  }

  private async assertInstallationInScope(
    user: AccessTokenClaims,
    installationId: string,
  ): Promise<void> {
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
    if (scope !== 'all' && !scope.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }
}
