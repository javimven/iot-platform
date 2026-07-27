import { SetMetadata } from '@nestjs/common';

/** Marca un endpoint como accesible sin JWT (login, refresh, forgot-password...). */
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = (): ReturnType<typeof SetMetadata> => SetMetadata(IS_PUBLIC_KEY, true);
