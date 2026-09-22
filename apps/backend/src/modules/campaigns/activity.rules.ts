import { BadRequestException } from '@nestjs/common';
import { hectareas } from './campaign.presenter';
import {
  ActivityTargetDto,
  FertilizationDetailDto,
  HarvestDetailDto,
  IrrigationDetailDto,
  PhytosanitaryDetailDto,
  TipoDeActividad,
} from './dto/activity.dto';

/**
 * Reglas de las actividades que no dependen de la base (ADR-0012/0013). Se
 * rechaza lo incoherente, nunca lo incompleto: el cuaderno completo avisa de
 * lo que falta, pero no impide apuntar un tratamiento a medias en el campo.
 */

export const CLAVES_DE_DETALLE = [
  'irrigation',
  'fertilization',
  'phytosanitary',
  'harvest',
  'fieldWork',
] as const;
export type ClaveDeDetalle = (typeof CLAVES_DE_DETALLE)[number];

/** Qué detalle lleva cada tipo. Observación, siembra y "otra" no llevan. */
export const DETALLE_DEL_TIPO: Partial<Record<TipoDeActividad, ClaveDeDetalle>> = {
  irrigation: 'irrigation',
  fertilization: 'fertilization',
  phytosanitary: 'phytosanitary',
  harvest: 'harvest',
  field_work: 'fieldWork',
};

type ConDetalles = Partial<Record<ClaveDeDetalle, unknown>>;

/**
 * El detalle tiene que ser el de su tipo, y lo que identifica la actividad
 * tiene que estar: qué se aplicó, con qué producto, qué labor. En el alta
 * además hace falta el detalle de los tipos que no se entienden sin él.
 */
export function comprobarDetalle(
  tipo: TipoDeActividad,
  datos: ConDetalles,
  momento: 'alta' | 'cambio',
): void {
  const propia = DETALLE_DEL_TIPO[tipo];
  for (const clave of CLAVES_DE_DETALLE) {
    if (clave !== propia && datos[clave] !== undefined) {
      throw new BadRequestException(`Una actividad de tipo "${tipo}" no lleva "${clave}".`);
    }
  }

  if (momento === 'alta') {
    if (tipo === 'field_work' && !datos.fieldWork) {
      throw new BadRequestException('Falta qué labor se hizo.');
    }
    if (tipo === 'fertilization' && !datos.fertilization) {
      throw new BadRequestException('Falta qué se ha aplicado: el producto o el tipo de material.');
    }
    if (tipo === 'phytosanitary' && !datos.phytosanitary) {
      throw new BadRequestException('Falta el producto del tratamiento.');
    }
  }

  const riego = datos.irrigation as IrrigationDetailDto | undefined;
  if (riego) {
    parValorUnidad(riego.amount, riego.amountUnit, 'la cantidad de agua');
  }
  const abono = datos.fertilization as FertilizationDetailDto | undefined;
  if (abono) {
    if (!abono.productName?.trim() && !abono.materialType) {
      throw new BadRequestException('Falta qué se ha aplicado: el producto o el tipo de material.');
    }
    parValorUnidad(abono.dose, abono.doseUnit, 'la dosis');
  }
  const tratamiento = datos.phytosanitary as PhytosanitaryDetailDto | undefined;
  if (tratamiento) {
    for (const producto of tratamiento.products) {
      parValorUnidad(producto.dose, producto.doseUnit, `la dosis de "${producto.productName}"`);
      parValorUnidad(
        producto.totalQuantity,
        producto.totalQuantityUnit,
        `la cantidad total de "${producto.productName}"`,
      );
    }
  }
  const cosecha = datos.harvest as HarvestDetailDto | undefined;
  if (cosecha) {
    parValorUnidad(cosecha.quantity, cosecha.quantityUnit, 'la cantidad cosechada');
  }
}

/** Un número sin unidad no significa nada, y una unidad sin número tampoco. */
function parValorUnidad(valor: number | undefined, unidad: string | undefined, que: string) {
  if ((valor === undefined) !== (unidad === undefined)) {
    throw new BadRequestException(`Para ${que} hacen falta el valor y su unidad.`);
  }
}

/** Una parcela de la campaña, en una unidad, con la superficie que ocupa en ella. */
export interface ParcelaDeCampana {
  cropUnitId: string;
  parcelId: string;
  parcelName: string;
  cropName: string;
  /** Lo que ocupa en la unidad: lo declarado o la parcela entera. */
  areaHa: number;
}

export interface Destino {
  cropUnitId: string;
  parcelId: string;
  /** Lo declarado para esta actividad; nulo = todo lo que ocupa en la unidad. */
  areaHa: number | null;
  effectiveAreaHa: number;
}

const MARGEN_SUPERFICIE = 1.02;

/**
 * A qué unidad de cultivo va cada parcela. Casi siempre una parcela está en
 * una sola unidad de la campaña y no hace falta decirlo; si está en dos (dos
 * cultivos asociados), hay que elegir.
 */
export function resolverDestinos(
  pedidos: ActivityTargetDto[],
  deLaCampana: ParcelaDeCampana[],
): Destino[] {
  const vistos = new Set<string>();
  return pedidos.map((pedido) => {
    const candidatas = deLaCampana.filter(
      (p) =>
        p.parcelId === pedido.parcelId &&
        (pedido.cropUnitId === undefined || p.cropUnitId === pedido.cropUnitId),
    );
    if (candidatas.length === 0) {
      throw new BadRequestException('Alguna parcela no es de esta campaña.');
    }
    if (candidatas.length > 1) {
      throw new BadRequestException(
        `La parcela "${candidatas[0].parcelName}" está en más de una unidad de cultivo: indica en cuál.`,
      );
    }
    const parcela = candidatas[0];
    const clave = `${parcela.cropUnitId}:${parcela.parcelId}`;
    if (vistos.has(clave)) {
      throw new BadRequestException(`La parcela "${parcela.parcelName}" está dos veces.`);
    }
    vistos.add(clave);
    if (pedido.areaHa !== undefined && pedido.areaHa > parcela.areaHa * MARGEN_SUPERFICIE) {
      throw new BadRequestException(
        `En "${parcela.parcelName}" no hay ${pedido.areaHa} ha de ${parcela.cropName}: hay ${hectareas(parcela.areaHa)} ha.`,
      );
    }
    return {
      cropUnitId: parcela.cropUnitId,
      parcelId: parcela.parcelId,
      areaHa: pedido.areaHa ?? null,
      effectiveAreaHa: hectareas(pedido.areaHa ?? parcela.areaHa),
    };
  });
}

export function superficieDe(destinos: Array<{ effectiveAreaHa: number }>): number {
  return hectareas(destinos.reduce((suma, d) => suma + d.effectiveAreaHa, 0));
}

function redondear(valor: number, decimales: number): number {
  const factor = 10 ** decimales;
  return Math.round(valor * factor) / factor;
}

/**
 * Metros cúbicos totales de un riego, se escribiera como se escribiera.
 * "18 m³/ha" en 0,85 ha son 15,3 m³.
 */
export function volumenM3(
  cantidad: number | null | undefined,
  unidad: string | null | undefined,
  superficieHa: number,
): number | null {
  if (cantidad == null || !unidad) {
    return null;
  }
  switch (unidad) {
    case 'm3':
      return redondear(cantidad, 3);
    case 'l':
      return redondear(cantidad / 1000, 3);
    case 'm3_ha':
      return redondear(cantidad * superficieHa, 3);
    default:
      return null;
  }
}

/**
 * Kilos de un nutriente por hectárea a partir de la dosis y la riqueza (%).
 * Solo cuando la dosis va en peso: una dosis en litros o en m³ necesitaría la
 * densidad, y no se inventa. En ese caso, nulo, y el resumen lo dice.
 */
export function nutrienteKgHa(
  dosis: number | null | undefined,
  unidad: string | null | undefined,
  riquezaPct: number | null | undefined,
  superficieHa: number,
): number | null {
  if (dosis == null || !unidad || riquezaPct == null) {
    return null;
  }
  const fraccion = riquezaPct / 100;
  switch (unidad) {
    case 'kg_ha':
      return redondear(dosis * fraccion, 2);
    case 't_ha':
      return redondear(dosis * 1000 * fraccion, 2);
    case 'kg':
      return superficieHa > 0 ? redondear((dosis / superficieHa) * fraccion, 2) : null;
    case 't':
      return superficieHa > 0 ? redondear(((dosis * 1000) / superficieHa) * fraccion, 2) : null;
    default:
      return null;
  }
}

/** Kilos cosechados; nulo si se contó en unidades (piezas, cajas). */
export function kilosCosechados(
  cantidad: number | null | undefined,
  unidad: string | null | undefined,
): number | null {
  if (cantidad == null || !unidad) {
    return null;
  }
  if (unidad === 'kg') {
    return redondear(cantidad, 3);
  }
  if (unidad === 't') {
    return redondear(cantidad * 1000, 3);
  }
  return null;
}

/** Hoy en UTC, con un día de margen por los husos: no se registra el futuro. */
export function comprobarQueNoEsFuturo(fecha: Date, ahora: Date = new Date()): void {
  const manana = Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth(), ahora.getUTCDate() + 1);
  if (fecha.getTime() > manana) {
    throw new BadRequestException('No se puede registrar algo que todavía no ha pasado.');
  }
}
