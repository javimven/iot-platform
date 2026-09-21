import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { GeoJsonMultiPolygon } from './parcel-geometry.service';

/**
 * Una parcela tal y como la devuelve la API: la geometría ya en GeoJSON, sin
 * rastro de cómo está guardada.
 */
export interface ParcelaConGeometria {
  id: string;
  organizationId: string;
  installationId: string;
  name: string;
  notes: string | null;
  geometry: GeoJsonMultiPolygon;
  areaM2: number;
  bbox: [number, number, number, number]; // [minLon, minLat, maxLon, maxLat]
  geometryVersion: number;
  createdAt: Date;
  updatedAt: Date;
}

interface FilaParcela {
  id: string;
  organization_id: string;
  installation_id: string;
  name: string;
  notes: string | null;
  geojson: string;
  area_m2: number;
  bbox_min_lon: number;
  bbox_min_lat: number;
  bbox_max_lon: number;
  bbox_max_lat: number;
  geometry_version: number;
  created_at: Date;
  updated_at: Date;
}

/**
 * El único sitio del backend que habla de geometría con la base de datos
 * (ADR-0009). Existe porque Prisma 5 no modela tipos de PostGIS: la columna
 * va declarada como `Unsupported`, así que **`prisma.parcel.create()` no es
 * utilizable** y `findMany` no devuelve la geometría. Aquí se resuelven esas
 * dos operaciones con SQL crudo, y el resto del módulo (servicio, controlador,
 * jobs de satélite) trabaja solo con GeoJSON.
 *
 * Cada método recibe el `tx` de `PrismaService.runInTenantContext` de quien
 * llama: el SQL crudo pasa por RLS igual que cualquier consulta de Prisma,
 * nunca por fuera.
 */
@Injectable()
export class ParcelsRepository {
  /**
   * Alta. PostGIS calcula el área sobre el elipsoide (`::geography`, metros de
   * verdad) y la caja envolvente: así no hay dos implementaciones de lo mismo
   * ni riesgo de que la caja deje de cuadrar con la geometría.
   *
   * `ST_IsValid` se comprueba antes de insertar para dar un mensaje claro: sin
   * eso, un polígono que se cruza a sí mismo entra en la tabla y revienta más
   * tarde, al pedirle el área o al mandarlo a Copernicus.
   */
  async crear(
    tx: Prisma.TransactionClient,
    datos: {
      organizationId: string;
      installationId: string;
      name: string;
      notes?: string | null;
      geometry: GeoJsonMultiPolygon;
    },
  ): Promise<ParcelaConGeometria> {
    const geojson = JSON.stringify(datos.geometry);
    await this.asegurarGeometriaValida(tx, geojson);

    const filas = await tx.$queryRaw<FilaParcela[]>`
      WITH entrada AS (
        SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${geojson}), 4326)) AS g
      )
      INSERT INTO parcels (organization_id, installation_id, name, notes, geometry, area_m2,
                           bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
      SELECT ${datos.organizationId}::uuid, ${datos.installationId}::uuid, ${datos.name},
             ${datos.notes ?? null}, g, ST_Area(g::geography),
             ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
      FROM entrada
      RETURNING id, organization_id, installation_id, name, notes,
                ST_AsGeoJSON(geometry) AS geojson, area_m2,
                bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat,
                geometry_version, created_at, updated_at
    `;
    return this.aParcela(filas[0]);
  }

  /**
   * Cambia el contorno: recalcula área y caja, y **sube `geometry_version`**.
   * Esa versión es la que permitirá saber que lo calculado por satélite antes
   * del cambio ya no corresponde a esta parcela.
   */
  async actualizarGeometria(
    tx: Prisma.TransactionClient,
    id: string,
    geometry: GeoJsonMultiPolygon,
  ): Promise<ParcelaConGeometria> {
    const geojson = JSON.stringify(geometry);
    await this.asegurarGeometriaValida(tx, geojson);

    const filas = await tx.$queryRaw<FilaParcela[]>`
      WITH entrada AS (
        SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${geojson}), 4326)) AS g
      )
      UPDATE parcels SET
        geometry = (SELECT g FROM entrada),
        area_m2 = (SELECT ST_Area(g::geography) FROM entrada),
        bbox_min_lon = (SELECT ST_XMin(g::box3d) FROM entrada),
        bbox_min_lat = (SELECT ST_YMin(g::box3d) FROM entrada),
        bbox_max_lon = (SELECT ST_XMax(g::box3d) FROM entrada),
        bbox_max_lat = (SELECT ST_YMax(g::box3d) FROM entrada),
        geometry_version = geometry_version + 1,
        updated_at = now()
      WHERE id = ${id}::uuid AND deleted_at IS NULL
      RETURNING id, organization_id, installation_id, name, notes,
                ST_AsGeoJSON(geometry) AS geojson, area_m2,
                bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat,
                geometry_version, created_at, updated_at
    `;
    return this.aParcela(filas[0]);
  }

  /** Una parcela por su id, con el contorno. Null si no existe o está borrada. */
  async porId(
    tx: Prisma.TransactionClient,
    id: string,
    organizationId: string,
  ): Promise<ParcelaConGeometria | null> {
    const filas = await tx.$queryRaw<FilaParcela[]>`
      SELECT id, organization_id, installation_id, name, notes,
             ST_AsGeoJSON(geometry) AS geojson, area_m2,
             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat,
             geometry_version, created_at, updated_at
      FROM parcels
      WHERE id = ${id}::uuid AND organization_id = ${organizationId}::uuid AND deleted_at IS NULL
    `;
    return filas.length === 0 ? null : this.aParcela(filas[0]);
  }

  /**
   * Las parcelas de una finca, con su contorno: el mapa las dibuja todas de
   * una vez, así que no tiene sentido una lista sin geometría y luego una
   * llamada por parcela.
   */
  async porInstalacion(
    tx: Prisma.TransactionClient,
    installationId: string,
  ): Promise<ParcelaConGeometria[]> {
    const filas = await tx.$queryRaw<FilaParcela[]>`
      SELECT id, organization_id, installation_id, name, notes,
             ST_AsGeoJSON(geometry) AS geojson, area_m2,
             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat,
             geometry_version, created_at, updated_at
      FROM parcels
      WHERE installation_id = ${installationId}::uuid AND deleted_at IS NULL
      ORDER BY name ASC
    `;
    return filas.map((fila) => this.aParcela(fila));
  }

  private async asegurarGeometriaValida(
    tx: Prisma.TransactionClient,
    geojson: string,
  ): Promise<void> {
    const filas = await tx.$queryRaw<Array<{ valida: boolean; motivo: string | null }>>`
      WITH entrada AS (SELECT ST_SetSRID(ST_GeomFromGeoJSON(${geojson}), 4326) AS g)
      SELECT ST_IsValid(g) AS valida, ST_IsValidReason(g) AS motivo FROM entrada
    `;
    if (!filas[0]?.valida) {
      throw new BadRequestException(
        `El contorno no es un recinto válido: ${filas[0]?.motivo ?? 'geometría inválida'}. ` +
          'Suele pasar cuando los lados se cruzan entre sí.',
      );
    }
  }

  private aParcela(fila: FilaParcela): ParcelaConGeometria {
    return {
      id: fila.id,
      organizationId: fila.organization_id,
      installationId: fila.installation_id,
      name: fila.name,
      notes: fila.notes,
      geometry: JSON.parse(fila.geojson) as GeoJsonMultiPolygon,
      areaM2: fila.area_m2,
      bbox: [fila.bbox_min_lon, fila.bbox_min_lat, fila.bbox_max_lon, fila.bbox_max_lat],
      geometryVersion: fila.geometry_version,
      createdAt: fila.created_at,
      updatedAt: fila.updated_at,
    };
  }
}
