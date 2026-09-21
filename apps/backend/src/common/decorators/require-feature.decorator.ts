import { SetMetadata } from '@nestjs/common';

/**
 * Codigos de `features` (prisma/seed.ts, PERMISSIONS.md §14) que hoy protegen
 * algun endpoint. No es el catalogo completo a proposito: solo se lista lo que
 * de verdad se comprueba en el backend, para que anotar una funcion
 * inexistente sea un error de compilacion.
 */
export type FeatureCode = 'satellite_imagery';

/**
 * Exige que la organizacion tenga contratada esa funcion (`FeatureGuard`).
 * Complementa a `@RequirePermission`, no lo sustituye: el permiso dice que
 * *ese rol* puede hacerlo, la funcion dice que *esa organizacion* lo tiene
 * contratado. Ocultarlo solo en la app no basta — la API es publica.
 */
export const REQUIRE_FEATURE_KEY = 'requireFeature';
export const RequireFeature = (feature: FeatureCode): ReturnType<typeof SetMetadata> =>
  SetMetadata(REQUIRE_FEATURE_KEY, feature);
