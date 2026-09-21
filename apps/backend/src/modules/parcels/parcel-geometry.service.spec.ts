import { BadRequestException } from '@nestjs/common';
import { ParcelGeometryService } from './parcel-geometry.service';

/**
 * Lo que se valida antes de que la geometría toque SQL (ADR-0009). El resto
 * —validez topológica, área, caja— lo hace PostGIS, y se comprueba en
 * `test/integration/parcels-rls.spec.ts` contra un Postgres real.
 */
describe('ParcelGeometryService', () => {
  const servicio = new ParcelGeometryService();

  const anillo = [
    [-0.5, 39.5],
    [-0.499, 39.5],
    [-0.499, 39.501],
    [-0.5, 39.501],
  ];

  it('normaliza un Polygon a MultiPolygon: se guarda siempre así', () => {
    const salida = servicio.normalizar({ type: 'Polygon', coordinates: [anillo] });

    expect(salida.type).toBe('MultiPolygon');
    expect(salida.coordinates).toHaveLength(1);
  });

  it('cierra el anillo si llega abierto, que es como lo dibuja la app', () => {
    const salida = servicio.normalizar({ type: 'Polygon', coordinates: [anillo] });
    const cerrado = salida.coordinates[0][0];

    expect(cerrado).toHaveLength(anillo.length + 1);
    expect(cerrado[cerrado.length - 1]).toEqual(cerrado[0]);
  });

  it('no añade un vértice si ya venía cerrado', () => {
    const yaCerrado = [...anillo, anillo[0]];
    const salida = servicio.normalizar({ type: 'Polygon', coordinates: [yaCerrado] });

    expect(salida.coordinates[0][0]).toHaveLength(yaCerrado.length);
  });

  it('acepta un MultiPolygon con varios recintos', () => {
    const segundo = anillo.map(([lon, lat]) => [lon + 0.01, lat]);
    const salida = servicio.normalizar({
      type: 'MultiPolygon',
      coordinates: [[anillo], [segundo]],
    });

    expect(salida.coordinates).toHaveLength(2);
  });

  it('rechaza un tipo que no es un recinto', () => {
    expect(() => servicio.normalizar({ type: 'Point', coordinates: [-0.5, 39.5] })).toThrow(
      BadRequestException,
    );
  });

  it('rechaza menos de tres vértices: no encierran superficie', () => {
    expect(() =>
      servicio.normalizar({
        type: 'Polygon',
        coordinates: [
          [
            [-0.5, 39.5],
            [-0.499, 39.5],
          ],
        ],
      }),
    ).toThrow(/tres vértices/);
  });

  it('rechaza coordenadas fuera del mundo, que es como se cuela un lat/lon invertido', () => {
    // [39.5, -0.5] con los componentes al revés: la latitud 39.5 pasa como
    // longitud sin problema, pero -0.5 como latitud también... el caso que sí
    // se detecta es el que se sale de rango.
    expect(() =>
      servicio.normalizar({
        type: 'Polygon',
        coordinates: [
          [
            [39.5, 181],
            [-0.499, 39.5],
            [-0.499, 39.501],
            [39.5, 181],
          ],
        ],
      }),
    ).toThrow(/Latitud fuera de rango/);
  });

  it('rechaza coordenadas que no son números', () => {
    expect(() =>
      servicio.normalizar({
        type: 'Polygon',
        coordinates: [
          [
            ['-0.5', 39.5],
            [-0.499, 39.5],
            [-0.499, 39.501],
          ],
        ],
      }),
    ).toThrow(/deben ser números/);
  });

  it('rechaza un contorno con demasiados vértices', () => {
    const enorme = Array.from({ length: 2001 }, (_, i) => [-0.5 + i * 1e-6, 39.5]);
    expect(() => servicio.normalizar({ type: 'Polygon', coordinates: [enorme] })).toThrow(
      /demasiados vértices/,
    );
  });

  it('rechaza lo que no es una geometría', () => {
    expect(() => servicio.normalizar(null)).toThrow(BadRequestException);
    expect(() => servicio.normalizar('{}')).toThrow(BadRequestException);
    expect(() => servicio.normalizar({ type: 'Polygon' })).toThrow(/coordenadas/);
  });
});
