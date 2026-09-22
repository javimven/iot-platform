import { applyDecorators } from '@nestjs/common';
import { IsDateString, Matches } from 'class-validator';

/**
 * Fechas sin hora del cuaderno (`2026-02-03`). Una campaña empieza "el 3 de
 * febrero" y una cosecha es "del 12 de septiembre": no hay hora que guardar,
 * y inventarse una en UTC es la forma clásica de que una fecha salga un día
 * antes en otro huso. En la base son `DATE`; en la API, texto `AAAA-MM-DD`.
 */
const FORMATO_FECHA = /^\d{4}-\d{2}-\d{2}$/;

/** Valida `AAAA-MM-DD` y que sea un día que existe (nada de 30 de febrero). */
export function EsFecha(): PropertyDecorator {
  return applyDecorators(Matches(FORMATO_FECHA), IsDateString({ strict: true }));
}

/** `2026-02-03` → el `Date` que Prisma guarda como ese `DATE`. */
export function leerFecha(texto: string): Date {
  return new Date(`${texto}T00:00:00.000Z`);
}

/** Un `DATE` leído de la base → `2026-02-03`. */
export function escribirFecha(fecha: Date): string {
  return fecha.toISOString().slice(0, 10);
}

export function escribirFechaONulo(fecha: Date | null | undefined): string | null {
  return fecha ? escribirFecha(fecha) : null;
}
