import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CampaignAccess } from './campaign-access';
import { escribirFechaONulo, leerFecha } from './fechas';
import {
  NotebookEquipmentCreateDto,
  NotebookEquipmentUpdateDto,
  NotebookListQueryDto,
  NotebookPersonCreateDto,
  NotebookPersonUpdateDto,
} from './dto/notebook.dto';

type PersonaGuardada = Prisma.NotebookPersonGetPayload<object>;
type EquipoGuardado = Prisma.NotebookEquipmentGetPayload<object>;

/**
 * Los dos catálogos se filtran igual (baja lógica y finca), así que el filtro
 * se escribe una vez. Con el tipo de una de las dos tablas, la otra no lo
 * acepta aunque las columnas sean las mismas.
 */
type FiltroDeCatalogo = {
  deletedAt?: null;
  OR?: Array<{ installationId: string | null | { in: string[] } }>;
};

/** Cómo se lee una persona en la app: el nombre ya montado, sin recomponerlo. */
export function presentarPersona(persona: PersonaGuardada) {
  const nombre = [persona.firstName, persona.surname1, persona.surname2]
    .filter((parte) => parte?.trim())
    .join(' ');
  return {
    id: persona.id,
    installationId: persona.installationId,
    kind: persona.kind,
    firstName: persona.firstName,
    surname1: persona.surname1,
    surname2: persona.surname2,
    companyName: persona.companyName,
    /** Lo que se enseña en una lista: la persona, o la empresa si no la hay. */
    displayName: nombre || persona.companyName || '',
    nif: persona.nif,
    ropoNumber: persona.ropoNumber,
    ropoCardType: persona.ropoCardType,
    notes: persona.notes,
    deleted: persona.deletedAt !== null,
  };
}

export function presentarEquipo(equipo: EquipoGuardado) {
  return {
    id: equipo.id,
    installationId: equipo.installationId,
    description: equipo.description,
    displayName: [equipo.description, equipo.brand, equipo.model]
      .filter((parte) => parte?.trim())
      .join(' · '),
    brand: equipo.brand,
    model: equipo.model,
    romaNumber: equipo.romaNumber,
    acquiredOn: escribirFechaONulo(equipo.acquiredOn),
    lastInspectionOn: escribirFechaONulo(equipo.lastInspectionOn),
    notes: equipo.notes,
    deleted: equipo.deletedAt !== null,
  };
}

/**
 * Catálogos del cuaderno completo (fase 5 del #60): quién trata, quién asesora
 * y con qué equipo. Dos tablas con el mismo trato, así que un solo servicio.
 *
 * Una entrada puede ser de una finca o valer para todas (`installationId`
 * nulo), que es lo normal en una explotación de un solo titular. El alcance
 * por finca del miembro (PERMISSIONS.md §2) se aplica igual que en campañas:
 * quien solo ve unas fincas ve sus entradas y las comunes.
 *
 * Baja lógica, nunca borrado: un tratamiento guarda la copia de la persona y
 * del equipo tal como eran ese día, pero el enlace sigue existiendo y el
 * historial tiene que poder resolverlo.
 */
@Injectable()
export class NotebookCatalogService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly acceso: CampaignAccess,
  ) {}

  async listPeople(user: AccessTokenClaims, filtros: NotebookListQueryDto) {
    const where = await this.filtro(user, filtros);
    const { tenantContext } = resolveOrgContext(user);
    const personas = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.notebookPerson.findMany({
        where: { ...where, ...(filtros.kind ? { kind: filtros.kind } : {}) },
        orderBy: [{ companyName: 'asc' }, { surname1: 'asc' }, { firstName: 'asc' }],
      }),
    );
    return personas.map(presentarPersona);
  }

  async createPerson(user: AccessTokenClaims, dto: NotebookPersonCreateDto) {
    comprobarIdentificacion(dto);
    await this.comprobarFinca(user, dto.installationId);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const persona = await tx.notebookPerson.create({
        data: {
          organizationId,
          installationId: dto.installationId ?? null,
          kind: dto.kind,
          ...camposDePersona(dto),
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_people.create',
        targetType: 'notebook_person',
        targetId: persona.id,
        metadata: { kind: persona.kind, name: presentarPersona(persona).displayName },
      });
      return presentarPersona(persona);
    });
  }

  async updatePerson(user: AccessTokenClaims, id: string, dto: NotebookPersonUpdateDto) {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const actual = await this.cargarPersona(user, id);
    // Cómo queda tras el cambio, campo a campo: lo que no viene en el DTO se
    // queda como está (un `undefined` no es "bórralo").
    comprobarIdentificacion({
      firstName: dto.firstName !== undefined ? dto.firstName : actual.firstName,
      companyName: dto.companyName !== undefined ? dto.companyName : actual.companyName,
    });
    await this.comprobarFinca(user, dto.installationId);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const persona = await tx.notebookPerson.update({
        where: { id },
        data: {
          ...(dto.kind ? { kind: dto.kind } : {}),
          ...(dto.installationId !== undefined
            ? { installationId: dto.installationId ?? null }
            : {}),
          ...camposDePersona(dto),
          updatedAt: new Date(),
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_people.update',
        targetType: 'notebook_person',
        targetId: id,
        metadata: { campos: Object.keys(dto) },
      });
      return presentarPersona(persona);
    });
  }

  async removePerson(user: AccessTokenClaims, id: string): Promise<void> {
    const actual = await this.cargarPersona(user, id);
    const { organizationId, tenantContext } = resolveOrgContext(user);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.notebookPerson.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_people.delete',
        targetType: 'notebook_person',
        targetId: id,
        metadata: { name: presentarPersona(actual).displayName },
      });
    });
  }

  async listEquipment(user: AccessTokenClaims, filtros: NotebookListQueryDto) {
    const where = await this.filtro(user, filtros);
    const { tenantContext } = resolveOrgContext(user);
    const equipos = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.notebookEquipment.findMany({ where, orderBy: { description: 'asc' } }),
    );
    return equipos.map(presentarEquipo);
  }

  async createEquipment(user: AccessTokenClaims, dto: NotebookEquipmentCreateDto) {
    await this.comprobarFinca(user, dto.installationId);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const equipo = await tx.notebookEquipment.create({
        data: {
          organizationId,
          installationId: dto.installationId ?? null,
          description: dto.description.trim(),
          ...camposDeEquipo(dto),
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_equipment.create',
        targetType: 'notebook_equipment',
        targetId: equipo.id,
        metadata: { description: equipo.description },
      });
      return presentarEquipo(equipo);
    });
  }

  async updateEquipment(user: AccessTokenClaims, id: string, dto: NotebookEquipmentUpdateDto) {
    await this.cargarEquipo(user, id);
    await this.comprobarFinca(user, dto.installationId);
    const { organizationId, tenantContext } = resolveOrgContext(user);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const equipo = await tx.notebookEquipment.update({
        where: { id },
        data: {
          ...(dto.description !== undefined ? { description: dto.description.trim() } : {}),
          ...(dto.installationId !== undefined
            ? { installationId: dto.installationId ?? null }
            : {}),
          ...camposDeEquipo(dto),
          updatedAt: new Date(),
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_equipment.update',
        targetType: 'notebook_equipment',
        targetId: id,
        metadata: { campos: Object.keys(dto) },
      });
      return presentarEquipo(equipo);
    });
  }

  async removeEquipment(user: AccessTokenClaims, id: string): Promise<void> {
    const actual = await this.cargarEquipo(user, id);
    const { organizationId, tenantContext } = resolveOrgContext(user);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.notebookEquipment.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'notebook_equipment.delete',
        targetType: 'notebook_equipment',
        targetId: id,
        metadata: { description: actual.description },
      });
    });
  }

  /**
   * Lo que este miembro puede ver: las entradas comunes y las de las fincas de
   * su alcance. Si pide una finca en concreto, esa y las comunes.
   */
  private async filtro(
    user: AccessTokenClaims,
    filtros: NotebookListQueryDto,
  ): Promise<FiltroDeCatalogo> {
    const vivas = filtros.includeDeleted ? {} : { deletedAt: null };
    if (filtros.installationId) {
      await this.acceso.asegurarFincaEnAlcance(user, filtros.installationId);
      return {
        ...vivas,
        OR: [{ installationId: filtros.installationId }, { installationId: null }],
      };
    }
    const alcance = await this.acceso.alcance(user);
    if (alcance === 'all') {
      return vivas;
    }
    return { ...vivas, OR: [{ installationId: { in: alcance } }, { installationId: null }] };
  }

  private async comprobarFinca(
    user: AccessTokenClaims,
    installationId: string | null | undefined,
  ): Promise<void> {
    if (installationId) {
      await this.acceso.asegurarFincaEnAlcance(user, installationId);
    }
  }

  private async cargarPersona(user: AccessTokenClaims, id: string): Promise<PersonaGuardada> {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const persona = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.notebookPerson.findFirst({ where: { id, organizationId, deletedAt: null } }),
    );
    if (!persona) {
      throw new NotFoundException('Notebook person not found');
    }
    await this.comprobarFinca(user, persona.installationId);
    return persona;
  }

  private async cargarEquipo(user: AccessTokenClaims, id: string): Promise<EquipoGuardado> {
    const { organizationId, tenantContext } = resolveOrgContext(user);
    const equipo = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.notebookEquipment.findFirst({ where: { id, organizationId, deletedAt: null } }),
    );
    if (!equipo) {
      throw new NotFoundException('Notebook equipment not found');
    }
    await this.comprobarFinca(user, equipo.installationId);
    return equipo;
  }
}

/** O una persona con nombre, o una empresa con razón social (CHECK de la 0011). */
function comprobarIdentificacion(datos: {
  firstName?: string | null;
  companyName?: string | null;
}): void {
  if (!datos.firstName?.trim() && !datos.companyName?.trim()) {
    throw new BadRequestException('Hace falta un nombre o una razón social.');
  }
}

/** Solo lo que viene en el DTO: lo omitido no se toca; `''` borra el dato. */
function texto(valor: string | undefined): string | null | undefined {
  if (valor === undefined) {
    return undefined;
  }
  return valor.trim() === '' ? null : valor.trim();
}

function camposDePersona(dto: NotebookPersonCreateDto | NotebookPersonUpdateDto) {
  return {
    firstName: texto(dto.firstName),
    surname1: texto(dto.surname1),
    surname2: texto(dto.surname2),
    companyName: texto(dto.companyName),
    // El NIF, en mayúsculas siempre: se busca por él y "12345678z" y
    // "12345678Z" son el mismo. `null` sigue siendo borrarlo.
    nif: typeof texto(dto.nif) === 'string' ? texto(dto.nif)!.toUpperCase() : texto(dto.nif),
    ropoNumber: texto(dto.ropoNumber),
    ropoCardType: texto(dto.ropoCardType),
    notes: texto(dto.notes),
  };
}

function camposDeEquipo(dto: NotebookEquipmentCreateDto | NotebookEquipmentUpdateDto) {
  return {
    brand: texto(dto.brand),
    model: texto(dto.model),
    romaNumber: texto(dto.romaNumber),
    acquiredOn: dto.acquiredOn === undefined ? undefined : leerFecha(dto.acquiredOn),
    lastInspectionOn:
      dto.lastInspectionOn === undefined ? undefined : leerFecha(dto.lastInspectionOn),
    notes: texto(dto.notes),
  };
}
