import { BadRequestException, Injectable } from '@nestjs/common';

/**
 * Anillo de coordenadas `[lon, lat]` — el orden de GeoJSON (RFC 7946), que es
 * el contrario al que se escribe a mano ("latitud, longitud"). Confundirlos
 * coloca la parcela en otro continente, así que se valida el rango de cada
 * componente por separado.
 */
export type Posicion = [number, number];

export interface GeoJsonPolygon {
  type: 'Polygon';
  coordinates: Posicion[][];
}

export interface GeoJsonMultiPolygon {
  type: 'MultiPolygon';
  coordinates: Posicion[][][];
}

export type GeometriaParcela = GeoJsonPolygon | GeoJsonMultiPolygon;

/** Un anillo necesita 3 vértices distintos + el de cierre (RFC 7946 §3.1.6). */
const MINIMO_POSICIONES_ANILLO = 4;

/** Tope defensivo: un contorno dibujado a mano no tiene miles de vértices. */
const MAXIMO_POSICIONES_ANILLO = 2000;

/**
 * Lo único que sabe de geometría fuera de la base de datos (ADR-0009). Valida
 * y normaliza el GeoJSON que llega de la app **antes** de que toque SQL; los
 * cálculos de verdad (área sobre el elipsoide, caja envolvente, validez
 * topológica) los hace PostGIS en `ParcelsRepository`, que es quien sabe
 * hacerlos bien.
 *
 * Aquí se queda solo lo que conviene rechazar pronto y con un mensaje que el
 * usuario entienda: tipo admitido, coordenadas dentro del mundo, anillos
 * cerrados y un tamaño razonable.
 */
@Injectable()
export class ParcelGeometryService {
  /**
   * Devuelve el contorno normalizado a MultiPolygon (ADR-0009: se guarda
   * siempre así, aunque la v1 solo deje dibujar un recinto).
   */
  normalizar(entrada: unknown): GeoJsonMultiPolygon {
    const geometria = this.comoGeometria(entrada);

    const poligonos: Posicion[][][] =
      geometria.type === 'Polygon' ? [geometria.coordinates] : geometria.coordinates;

    if (poligonos.length === 0) {
      throw new BadRequestException('El contorno no tiene ningún recinto.');
    }

    return {
      type: 'MultiPolygon',
      coordinates: poligonos.map((poligono, i) => this.normalizarPoligono(poligono, i)),
    };
  }

  private comoGeometria(entrada: unknown): GeometriaParcela {
    if (typeof entrada !== 'object' || entrada === null) {
      throw new BadRequestException('El contorno debe ser una geometría GeoJSON.');
    }
    const { type, coordinates } = entrada as { type?: unknown; coordinates?: unknown };
    if (type !== 'Polygon' && type !== 'MultiPolygon') {
      throw new BadRequestException(
        `Tipo de geometría no admitido: ${String(type)}. Se espera Polygon o MultiPolygon.`,
      );
    }
    if (!Array.isArray(coordinates)) {
      throw new BadRequestException('El contorno no trae coordenadas.');
    }
    return entrada as GeometriaParcela;
  }

  private normalizarPoligono(poligono: unknown, indice: number): Posicion[][] {
    if (!Array.isArray(poligono) || poligono.length === 0) {
      throw new BadRequestException(`El recinto ${indice + 1} no tiene ningún anillo.`);
    }
    // El primer anillo es el contorno exterior; los siguientes son huecos
    // (RFC 7946). La v1 no dibuja huecos, pero si llegaran se conservan.
    return poligono.map((anillo) => this.normalizarAnillo(anillo, indice));
  }

  private normalizarAnillo(anillo: unknown, indicePoligono: number): Posicion[] {
    if (!Array.isArray(anillo)) {
      throw new BadRequestException(`El recinto ${indicePoligono + 1} tiene un anillo inválido.`);
    }

    const posiciones = anillo.map((posicion) => this.normalizarPosicion(posicion));

    if (posiciones.length > MAXIMO_POSICIONES_ANILLO) {
      throw new BadRequestException(
        `El contorno tiene demasiados vértices (máximo ${MAXIMO_POSICIONES_ANILLO}).`,
      );
    }

    const cerrado = this.cerrar(posiciones);
    if (cerrado.length < MINIMO_POSICIONES_ANILLO) {
      throw new BadRequestException(
        'Un recinto necesita al menos tres vértices distintos para encerrar una superficie.',
      );
    }
    return cerrado;
  }

  private normalizarPosicion(posicion: unknown): Posicion {
    if (!Array.isArray(posicion) || posicion.length < 2) {
      throw new BadRequestException('Cada vértice debe ser un par [longitud, latitud].');
    }
    const [lon, lat] = posicion;
    if (typeof lon !== 'number' || typeof lat !== 'number' || !isFinite(lon) || !isFinite(lat)) {
      throw new BadRequestException('Las coordenadas del contorno deben ser números.');
    }
    if (lon < -180 || lon > 180) {
      throw new BadRequestException(
        `Longitud fuera de rango: ${lon} (se espera entre -180 y 180).`,
      );
    }
    if (lat < -90 || lat > 90) {
      throw new BadRequestException(`Latitud fuera de rango: ${lat} (se espera entre -90 y 90).`);
    }
    // Se descarta la altura si viniera: la parcela es plana sobre el elipsoide
    // y PostGIS guarda geometría 2D.
    return [lon, lat];
  }

  /**
   * GeoJSON exige que el último vértice repita el primero. La app dibuja
   * tocando puntos y cierra el polígono al guardar, así que el anillo llega
   * abierto casi siempre; se cierra aquí en vez de obligar al cliente.
   */
  private cerrar(posiciones: Posicion[]): Posicion[] {
    if (posiciones.length === 0) {
      throw new BadRequestException('Un recinto necesita vértices.');
    }
    const primera = posiciones[0];
    const ultima = posiciones[posiciones.length - 1];
    if (primera[0] === ultima[0] && primera[1] === ultima[1]) {
      return posiciones;
    }
    return [...posiciones, primera];
  }
}
