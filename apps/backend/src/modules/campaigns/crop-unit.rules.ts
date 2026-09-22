import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { CropUnitCreateDto, CropUnitParcelDto } from './dto/crop-unit.dto';
import { hectareas } from './campaign.presenter';

/**
 * Reglas de una unidad de cultivo que no dependen de si se crea con la
 * campaña o se añade después. Las comprueba el servicio antes de tocar la
 * base: los CHECK y triggers de la migración 0010 son la red de seguridad,
 * pero un error de Postgres no le dice nada a quien está rellenando la
 * pantalla.
 */

/**
 * Margen para comparar lo declarado con la superficie de la parcela. La de la
 * parcela sale del contorno dibujado en el mapa, y la declarada suele venir
 * del SIGPAC o de la escritura: difieren un poco sin que nadie se equivoque.
 */
const MARGEN_SUPERFICIE = 1.02;

export function comprobarParcelasSinRepetir(parcelas: CropUnitParcelDto[]): void {
  const vistas = new Set<string>();
  for (const { parcelId } of parcelas) {
    if (vistas.has(parcelId)) {
      throw new BadRequestException('La misma parcela está dos veces en la unidad de cultivo.');
    }
    vistas.add(parcelId);
  }
}

/** Lo declarado de una parcela no puede ser más que la parcela. */
export function comprobarSuperficies(
  parcelas: CropUnitParcelDto[],
  deLaFinca: Map<string, { name: string; areaHa: number }>,
): void {
  for (const { parcelId, areaHa } of parcelas) {
    const parcela = deLaFinca.get(parcelId);
    if (parcela && areaHa !== undefined && areaHa > parcela.areaHa * MARGEN_SUPERFICIE) {
      throw new BadRequestException(
        `La superficie declarada en "${parcela.name}" (${areaHa} ha) es mayor que la de la parcela (${hectareas(parcela.areaHa)} ha).`,
      );
    }
  }
}

/** Los cultivos del catálogo que se nombran, activos; 400 si alguno no existe. */
export async function cultivosDelCatalogo(
  tx: Prisma.TransactionClient,
  ids: Array<string | undefined>,
): Promise<Map<string, { id: string; name: string }>> {
  const pedidos = [...new Set(ids.filter((id): id is string => Boolean(id)))];
  if (pedidos.length === 0) {
    return new Map();
  }
  const cultivos = await tx.crop.findMany({
    where: { id: { in: pedidos }, active: true },
    select: { id: true, name: true },
  });
  const encontrados = new Map(cultivos.map((c) => [c.id, c]));
  const falta = pedidos.find((id) => !encontrados.has(id));
  if (falta) {
    throw new BadRequestException(`Cultivo desconocido: ${falta}`);
  }
  return encontrados;
}

/**
 * El nombre del cultivo que se guarda: el escrito, o el del catálogo. Se
 * guarda siempre, para que un cuaderno cerrado no cambie si se renombra el
 * catálogo (ADR-0012).
 */
export function nombreDelCultivo(
  unidad: Pick<CropUnitCreateDto, 'cropId' | 'cropName'>,
  cultivos: Map<string, { name: string }>,
): string {
  const escrito = unidad.cropName?.trim();
  if (escrito) {
    return escrito;
  }
  const delCatalogo = unidad.cropId ? cultivos.get(unidad.cropId)?.name : undefined;
  if (!delCatalogo) {
    throw new BadRequestException('Falta el cultivo: elígelo del catálogo o escribe su nombre.');
  }
  return delCatalogo;
}

/** Los campos de la unidad tal como se guardan (sin las parcelas). */
export function datosDeUnidad(
  unidad: CropUnitCreateDto,
  cultivos: Map<string, { name: string }>,
  organizationId: string,
) {
  return {
    organizationId,
    cropId: unidad.cropId ?? null,
    cropName: nombreDelCultivo(unidad, cultivos),
    variety: unidad.variety?.trim() || null,
    previousCrop: unidad.previousCrop?.trim() || null,
    waterRegime: unidad.waterRegime ?? null,
    growingEnvironment: unidad.growingEnvironment ?? null,
    productionSystem: unidad.productionSystem ?? null,
    areaHa: unidad.areaHa ?? null,
    expectedYieldKgHa: unidad.expectedYieldKgHa ?? null,
    notes: unidad.notes ?? null,
  };
}

export function parcelasParaGuardar(parcelas: CropUnitParcelDto[], organizationId: string) {
  return parcelas.map((p) => ({ parcelId: p.parcelId, organizationId, areaHa: p.areaHa ?? null }));
}
