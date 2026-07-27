import { Injectable } from '@nestjs/common';
import { User } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Búsqueda por email para login — sin contexto de organización todavía
   * (`users` no tiene RLS, DATA_MODEL.md §7: es identidad global, el control
   * de acceso a esta tabla es responsabilidad de la capa de aplicación, nunca
   * un listado abierto).
   */
  async findByEmail(email: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { email } });
  }

  async findById(id: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id } });
  }

  async isPlatformAdmin(userId: string): Promise<boolean> {
    const record = await this.prisma.platformAdmin.findUnique({ where: { userId } });
    return record !== null;
  }

  /** Usado por accept-invitation y reset-password (ambos ya verificaron el token antes de llamar). */
  async updatePasswordHash(userId: string, passwordHash: string): Promise<void> {
    await this.prisma.user.update({ where: { id: userId }, data: { passwordHash } });
  }
}
