import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FeatureCode, REQUIRE_FEATURE_KEY } from '../decorators/require-feature.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { AuthenticatedRequest } from './jwt-auth.guard';

/**
 * Comprueba en el backend las funciones contratadas por la organizacion
 * (PERMISSIONS.md §14), para los endpoints anotados con `@RequireFeature`.
 *
 * Hasta ahora el gating era solo de interfaz: la app enseñaba
 * `LockedFeatureScreen` y ya. Eso vale para una seccion vacia, pero no para
 * una que llama a una API de pago por peticion (Copernicus): sin esto, una
 * organizacion sin el modulo contratado solo tenia que llamar a la ruta a
 * mano.
 *
 * Es un guard a proposito, y no una comprobacion repetida en cada servicio:
 * una anotacion en la clase del controlador cubre todas sus rutas.
 */
@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const exigidas = this.reflector.getAllAndOverride<FeatureCode[] | FeatureCode | undefined>(
      REQUIRE_FEATURE_KEY,
      [context.getHandler(), context.getClass()],
    );
    const features = exigidas === undefined ? [] : ([] as FeatureCode[]).concat(exigidas);
    if (features.length === 0) {
      return true;
    }

    const { authContext } = context.switchToHttp().getRequest<AuthenticatedRequest>();

    // El Admin de plataforma administra organizaciones ajenas (ADR-0005): no
    // tiene funciones contratadas propias y no se le bloquea por esto. Lo que
    // si sigue acotandolo es su permiso y, en las rutas de miembro, no tener
    // organizacion activa.
    if (authContext.isPlatformAdmin && !authContext.organizationId) {
      return true;
    }

    const organizationId = authContext.organizationId;
    if (!organizationId) {
      throw new ForbiddenException('No active organization');
    }

    const contratada = await this.prisma.runInTenantContext(
      { userId: authContext.sub, organizationId },
      (tx) =>
        tx.organizationFeature.findFirst({
          // Cualquiera de ellas basta (ver `@RequireFeature`).
          where: { organizationId, featureCode: { in: features }, enabled: true },
        }),
    );

    if (!contratada) {
      throw new ForbiddenException(
        `Feature not enabled for this organization: ${features.join(', ')}`,
      );
    }
    return true;
  }
}
