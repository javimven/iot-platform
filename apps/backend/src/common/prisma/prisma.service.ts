import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';

/**
 * Contexto de tenant de una petición (DATA_MODEL.md §7, SECURITY.md §1).
 * `userId` habilita la excepción "propio usuario" de members/sessions
 * descubierta al implementar el login (ver migration 0002).
 */
export interface TenantContext {
  userId?: string;
  organizationId?: string;
  isPlatformAdmin?: boolean;
  /**
   * Habilita localizar una fila de `members`/`sessions` por su propia PK
   * antes de conocer `userId`/`organizationId` (flujos de refresh de sesión
   * y de aceptación de invitación, DATA_MODEL.md §3/§7) — generalizada en
   * Etapa 13 a partir de lo que empezó siendo solo para sesiones. Sigue
   * siendo deliberadamente distinta de `isPlatformAdmin` (acotada al
   * Directorio IoT, ADR-0005) — no se reutiliza para eso.
   */
  allowIdentityBootstrap?: boolean;
}

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }

  /**
   * Ejecuta `fn` dentro de una transacción con las variables de sesión de RLS
   * fijadas vía `set_config(..., true)` parametrizado — nunca `SET`/`SET LOCAL`
   * con el valor interpolado en la sentencia (SECURITY.md §1, corrección de la
   * Etapa 8). El efecto es local a la transacción: imprescindible con un pool
   * de conexiones reutilizadas entre peticiones de distintas organizaciones.
   */
  async runInTenantContext<T>(
    context: TenantContext,
    fn: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    return this.$transaction(async (tx) => {
      // `null`, no `''`: las políticas de RLS castean estas dos variables a
      // `::uuid` (DATA_MODEL.md §7) — `''::uuid` lanza un error real de
      // Postgres ("invalid input syntax for type uuid"), mientras que
      // `NULL::uuid` es simplemente NULL (la comparación de la política
      // correspondiente da `false`, no un error). Descubierto en vivo
      // (2026-07-28): invisible mientras la conexión de la aplicación
      // pudiera saltarse RLS (ver infra/docker/postgres-init) — con RLS
      // realmente activo, cualquier login (organizationId aún desconocido)
      // rompía con un 500.
      await tx.$executeRaw`SELECT set_config('app.current_user_id', ${context.userId ?? null}, true)`;
      await tx.$executeRaw`SELECT set_config('app.current_org_id', ${context.organizationId ?? null}, true)`;
      await tx.$executeRaw`SELECT set_config('app.is_platform_admin', ${
        context.isPlatformAdmin ? 'true' : 'false'
      }, true)`;
      await tx.$executeRaw`SELECT set_config('app.allow_identity_bootstrap', ${
        context.allowIdentityBootstrap ? 'true' : 'false'
      }, true)`;
      return fn(tx);
    });
  }
}
