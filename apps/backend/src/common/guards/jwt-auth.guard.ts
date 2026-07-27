import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { JwtService } from '@nestjs/jwt';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { RoleCode } from '../permissions/permissions';

/**
 * Claims del access token (ARCHITECTURE.md §6). `organizationId`/`roleCode`
 * ausentes = Admin de plataforma sin organización activa. `type` distingue un
 * access token normal de un preAuthToken (API_DESIGN.md §3, solo válido en
 * /auth/select-organization).
 */
export interface AccessTokenClaims {
  sub: string; // userId
  type: 'access' | 'pre_auth';
  organizationId?: string;
  roleCode?: RoleCode;
  isPlatformAdmin?: boolean;
  /** Id de `members` (no de `users`) — necesario para el alcance por instalación (PERMISSIONS.md §2). */
  memberId?: string;
}

export interface AuthenticatedRequest extends Request {
  authContext: AccessTokenClaims;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = this.extractToken(request);
    if (!token) {
      throw new UnauthorizedException('Missing bearer token');
    }

    try {
      const claims = await this.jwtService.verifyAsync<AccessTokenClaims>(token);
      if (claims.type !== 'access') {
        // Un preAuthToken nunca es válido fuera de /auth/select-organization
        // (API_DESIGN.md §3) — esa ruta no pasa por este guard (es @Public()
        // y valida el preAuthToken explícitamente en el servicio).
        throw new UnauthorizedException('Token is not an access token');
      }
      request.authContext = claims;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }
  }

  private extractToken(request: Request): string | undefined {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return undefined;
    }
    return header.slice('Bearer '.length);
  }
}
