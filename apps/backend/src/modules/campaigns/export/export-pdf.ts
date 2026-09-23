import PDFDocument from 'pdfkit';
import {
  CATEGORIAS_DE_PROBLEMA,
  cifra,
  ENTORNOS,
  etiqueta,
  fecha,
  MATERIALES_FERTILIZANTES,
  METODOS_DE_APLICACION,
  REGIMENES_HIDRICOS,
  SISTEMAS_DE_RIEGO,
  SISTEMAS_PRODUCTIVOS,
  TIPOS_DE_ACTIVIDAD,
  TIPOS_DE_LABOR,
  UNIDADES,
} from './etiquetas';
import { ActividadExportada, CuadernoExportado } from './export-model';

/**
 * El cuaderno en PDF, en dos disposiciones (fase 7 del #60):
 *
 * - **`informe`**: para leerlo y enseñarlo. Primero lo que se resume de un
 *   vistazo (superficie, agua, nutrientes, cosecha) y después el detalle.
 * - **`cue`**: los mismos datos en el orden y con los nombres del Cuaderno
 *   Único de Explotación, para cotejarlo bloque a bloque con quien lo pida.
 *
 * **No es el formulario oficial ni una certificación** (ADR-0013): es lo
 * registrado, presentado de dos maneras. El pie de cada página lo dice, y
 * ninguna de las dos usa la palabra "cumple".
 *
 * Fuente estándar (Helvetica) y nada de subíndices: un PDF con fuentes
 * incrustadas pesaría diez veces más y `P₂O₅` saldría como un cuadrado.
 */
export type DisposicionDelPdf = 'informe' | 'cue';

const MARGEN = 48;
const ANCHO_UTIL = 595.28 - MARGEN * 2; // A4 vertical
const GRIS = '#4a4a4a';
const NEGRO = '#1a1a1a';

type Doc = PDFKit.PDFDocument;

interface Columna {
  titulo: string;
  ancho: number;
  /** Alinea a la derecha las cifras, que es como se comparan. */
  derecha?: boolean;
}

function titulo(doc: Doc, texto: string): void {
  reservar(doc, 30);
  doc.font('Helvetica-Bold').fontSize(13).fillColor(NEGRO).text(texto);
  doc.moveDown(0.4);
}

function parrafo(doc: Doc, texto: string, gris = false): void {
  doc
    .font('Helvetica')
    .fontSize(9)
    .fillColor(gris ? GRIS : NEGRO)
    .text(texto, { align: 'left' });
  doc.moveDown(0.3);
}

/** Pares "etiqueta: valor" en dos columnas, que es como se lee una ficha. */
function ficha(doc: Doc, datos: Array<[string, string]>): void {
  const vivos = datos.filter(([, valor]) => valor.trim().length > 0);
  const mitad = Math.ceil(vivos.length / 2);
  const columnas = [vivos.slice(0, mitad), vivos.slice(mitad)];
  const alto = mitad * 14;
  reservar(doc, alto + 8);
  const y = doc.y;

  columnas.forEach((columna, i) => {
    const x = MARGEN + i * (ANCHO_UTIL / 2);
    columna.forEach(([clave, valor], fila) => {
      const yFila = y + fila * 14;
      doc
        .font('Helvetica-Bold')
        .fontSize(8)
        .fillColor(GRIS)
        .text(`${clave}: `, x, yFila, {
          continued: true,
          width: ANCHO_UTIL / 2 - 8,
        });
      doc.font('Helvetica').fontSize(8).fillColor(NEGRO).text(valor);
    });
  });
  doc.y = y + alto + 6;
  doc.x = MARGEN;
}

/** Deja sitio en la página; si no cabe, pasa a la siguiente. */
function reservar(doc: Doc, alto: number): void {
  if (doc.y + alto > doc.page.height - MARGEN - 24) {
    doc.addPage();
  }
}

function tabla(doc: Doc, columnas: Columna[], filas: string[][]): void {
  if (filas.length === 0) {
    parrafo(doc, 'Sin registros.', true);
    return;
  }

  const cabecera = () => {
    const y = doc.y;
    let x = MARGEN;
    doc.font('Helvetica-Bold').fontSize(8).fillColor(GRIS);
    // El alto se mide, no se supone: un título que ocupa dos líneas con un
    // alto fijo se come la primera fila de datos.
    const alto = Math.max(
      ...columnas.map((columna) =>
        doc.heightOfString(columna.titulo, { width: columna.ancho - 6 }),
      ),
    );
    for (const columna of columnas) {
      doc.text(columna.titulo, x, y, {
        width: columna.ancho - 6,
        align: columna.derecha ? 'right' : 'left',
      });
      x += columna.ancho;
    }
    doc.y = y + alto + 4;
    doc
      .moveTo(MARGEN, doc.y - 4)
      .lineTo(MARGEN + ANCHO_UTIL, doc.y - 4)
      .strokeColor('#cccccc')
      .lineWidth(0.5)
      .stroke();
  };

  reservar(doc, 40);
  cabecera();

  for (const fila of filas) {
    const alto = Math.max(
      ...fila.map((celda, i) =>
        doc
          .font('Helvetica')
          .fontSize(8)
          .heightOfString(celda || ' ', {
            width: columnas[i].ancho - 6,
          }),
      ),
    );
    if (doc.y + alto > doc.page.height - MARGEN - 24) {
      doc.addPage();
      cabecera();
    }
    const y = doc.y;
    let x = MARGEN;
    fila.forEach((celda, i) => {
      doc
        .font('Helvetica')
        .fontSize(8)
        .fillColor(NEGRO)
        .text(celda, x, y, {
          width: columnas[i].ancho - 6,
          align: columnas[i].derecha ? 'right' : 'left',
        });
      x += columnas[i].ancho;
    });
    doc.y = y + alto + 4;
    doc.x = MARGEN;
  }
  doc.moveDown(0.6);
}

function periodo(cuaderno: CuadernoExportado): string {
  const inicio = fecha(cuaderno.campaign.startDate);
  const fin = fecha(cuaderno.campaign.endDate ?? cuaderno.campaign.expectedEndDate);
  if (!fin) {
    return `Desde el ${inicio}`;
  }
  return `Del ${inicio} al ${fin}${cuaderno.campaign.endDate ? '' : ' (previsto)'}`;
}

function resumenDeActividad(actividad: ActividadExportada): string {
  switch (actividad.type) {
    case 'irrigation': {
      const d = actividad.irrigation ?? {};
      const cantidad =
        d.amount == null ? '' : `${cifra(d.amount)} ${etiqueta(UNIDADES, d.amountUnit)}`;
      return [cantidad, etiqueta(SISTEMAS_DE_RIEGO, d.system)].filter(Boolean).join(' · ');
    }
    case 'fertilization': {
      const d = actividad.fertilization ?? {};
      const dosis = d.dose == null ? '' : `${cifra(d.dose)} ${etiqueta(UNIDADES, d.doseUnit)}`;
      return [
        typeof d.productName === 'string'
          ? d.productName
          : etiqueta(MATERIALES_FERTILIZANTES, d.materialType),
        dosis,
        etiqueta(METODOS_DE_APLICACION, d.applicationMethod),
      ]
        .filter(Boolean)
        .join(' · ');
    }
    case 'phytosanitary': {
      const d = actividad.phytosanitary;
      const productos = (d?.products ?? []).map((p) => String(p.productName ?? '')).filter(Boolean);
      const problema =
        typeof d?.problem === 'string' && d.problem
          ? d.problem
          : etiqueta(CATEGORIAS_DE_PROBLEMA, d?.problemCategory);
      return [productos.join(' + '), problema].filter(Boolean).join(' · ');
    }
    case 'harvest': {
      const d = actividad.harvest ?? {};
      return d.quantity == null ? '' : `${cifra(d.quantity)} ${etiqueta(UNIDADES, d.quantityUnit)}`;
    }
    case 'field_work':
      return etiqueta(TIPOS_DE_LABOR, actividad.fieldWork?.workType);
    default:
      // Una observación no tiene más resumen que sus notas, y esas ya van en
      // su propia columna: devolverlas aquí las imprimiría dos veces.
      return '';
  }
}

function cabeceraDeLaFinca(doc: Doc, cuaderno: CuadernoExportado): void {
  ficha(doc, [
    ['Explotación', cuaderno.installation.name],
    ['Titular', cuaderno.installation.holderName ?? ''],
    ['NIF', cuaderno.installation.holderNif ?? ''],
    ['Código REA', cuaderno.installation.reaCode ?? ''],
    ['Dirección', cuaderno.installation.address ?? ''],
    ['Comunidad autónoma', cuaderno.installation.regionCode ?? ''],
    ['Organización', cuaderno.organization.name ?? ''],
  ]);
}

function unidadesDeCultivo(doc: Doc, cuaderno: CuadernoExportado): void {
  tabla(
    doc,
    [
      // La suma de los anchos no puede pasar de ANCHO_UTIL (499): lo que
      // sobresale se sale del papel y no se ve.
      { titulo: 'Cultivo', ancho: 100 },
      { titulo: 'Variedad', ancho: 70 },
      { titulo: 'Régimen', ancho: 55 },
      { titulo: 'Sistema', ancho: 85 },
      { titulo: 'Entorno', ancho: 55 },
      { titulo: 'Parcelas', ancho: 94 },
      { titulo: 'ha', ancho: 40, derecha: true },
    ],
    cuaderno.cropUnits.map((unidad) => [
      unidad.cropName,
      unidad.variety ?? '',
      etiqueta(REGIMENES_HIDRICOS, unidad.waterRegime),
      etiqueta(SISTEMAS_PRODUCTIVOS, unidad.productionSystem),
      etiqueta(ENTORNOS, unidad.growingEnvironment),
      unidad.parcels.map((p) => p.name).join(', '),
      cifra(unidad.areaHa, 4),
    ]),
  );
}

function tablaDeTratamientos(doc: Doc, cuaderno: CuadernoExportado): void {
  const filas: string[][] = [];
  for (const actividad of cuaderno.activities.filter((a) => a.type === 'phytosanitary')) {
    const d = actividad.phytosanitary;
    const productos = d?.products ?? [];
    const base = [
      fecha(actividad.startDate) + (actividad.startTime ? ` ${actividad.startTime}` : ''),
      actividad.targets.map((t) => t.parcelName).join(', '),
      cifra(actividad.areaHa, 4),
    ];
    const contexto = [
      typeof d?.problem === 'string' && d.problem
        ? d.problem
        : etiqueta(CATEGORIAS_DE_PROBLEMA, d?.problemCategory),
      typeof d?.phenologicalStageLabel === 'string' ? d.phenologicalStageLabel : '',
      typeof d?.bbchCode === 'string' ? `BBCH ${d.bbchCode}` : '',
    ]
      .filter(Boolean)
      .join(' · ');

    if (productos.length === 0) {
      filas.push([...base, '', '', '', contexto]);
      continue;
    }
    for (const producto of productos) {
      filas.push([
        ...base,
        String(producto.productName ?? ''),
        String(producto.registryNumber ?? ''),
        producto.dose == null
          ? ''
          : `${cifra(producto.dose)} ${etiqueta(UNIDADES, producto.doseUnit)}`,
        contexto,
      ]);
    }
  }

  tabla(
    doc,
    [
      { titulo: 'Fecha', ancho: 72 },
      { titulo: 'Parcelas', ancho: 92 },
      { titulo: 'ha', ancho: 38, derecha: true },
      { titulo: 'Producto', ancho: 104 },
      { titulo: 'Nº registro', ancho: 58 },
      { titulo: 'Dosis', ancho: 55, derecha: true },
      { titulo: 'Plaga y estado', ancho: 80 },
    ],
    filas,
  );
}

function tablaDeAbonados(doc: Doc, cuaderno: CuadernoExportado): void {
  tabla(
    doc,
    [
      { titulo: 'Fecha', ancho: 72 },
      { titulo: 'Parcelas', ancho: 100 },
      { titulo: 'ha', ancho: 38, derecha: true },
      { titulo: 'Material o producto', ancho: 118 },
      { titulo: 'Dosis', ancho: 60, derecha: true },
      { titulo: 'Aplicación', ancho: 55 },
      { titulo: 'N-P2O5-K2O kg/ha', ancho: 56, derecha: true },
    ],
    cuaderno.activities
      .filter((a) => a.type === 'fertilization')
      .map((actividad) => {
        const d = actividad.fertilization ?? {};
        const nutrientes = [d.nKgHa, d.p2o5KgHa, d.k2oKgHa]
          .map((valor) => (valor == null ? '—' : cifra(valor, 1)))
          .join(' / ');
        return [
          fecha(actividad.startDate),
          actividad.targets.map((t) => t.parcelName).join(', '),
          cifra(actividad.areaHa, 4),
          typeof d.productName === 'string' && d.productName
            ? d.productName
            : etiqueta(MATERIALES_FERTILIZANTES, d.materialType),
          d.dose == null ? '' : `${cifra(d.dose)} ${etiqueta(UNIDADES, d.doseUnit)}`,
          etiqueta(METODOS_DE_APLICACION, d.applicationMethod),
          nutrientes,
        ];
      }),
  );
}

function tablaDeRiegos(doc: Doc, cuaderno: CuadernoExportado): void {
  tabla(
    doc,
    [
      { titulo: 'Desde', ancho: 66 },
      { titulo: 'Hasta', ancho: 66 },
      { titulo: 'Parcelas', ancho: 130 },
      { titulo: 'ha', ancho: 40, derecha: true },
      { titulo: 'Sistema', ancho: 90 },
      { titulo: 'Cantidad', ancho: 58, derecha: true },
      { titulo: 'm³ totales', ancho: 49, derecha: true },
    ],
    cuaderno.activities
      .filter((a) => a.type === 'irrigation')
      .map((actividad) => {
        const d = actividad.irrigation ?? {};
        return [
          fecha(actividad.startDate),
          fecha(actividad.endDate),
          actividad.targets.map((t) => t.parcelName).join(', '),
          cifra(actividad.areaHa, 4),
          etiqueta(SISTEMAS_DE_RIEGO, d.system),
          d.amount == null ? '' : `${cifra(d.amount)} ${etiqueta(UNIDADES, d.amountUnit)}`,
          cifra(d.volumeM3, 1),
        ];
      }),
  );
}

function tablaDeCosechas(doc: Doc, cuaderno: CuadernoExportado): void {
  tabla(
    doc,
    [
      { titulo: 'Fecha', ancho: 72 },
      { titulo: 'Parcelas', ancho: 120 },
      { titulo: 'ha', ancho: 40, derecha: true },
      { titulo: 'Producto', ancho: 100 },
      { titulo: 'Cantidad', ancho: 70, derecha: true },
      { titulo: 'Destino o lote', ancho: 97 },
    ],
    cuaderno.activities
      .filter((a) => a.type === 'harvest')
      .map((actividad) => {
        const d = actividad.harvest ?? {};
        return [
          fecha(actividad.startDate),
          actividad.targets.map((t) => t.parcelName).join(', '),
          cifra(actividad.areaHa, 4),
          typeof d.product === 'string' ? d.product : '',
          d.quantity == null ? '' : `${cifra(d.quantity)} ${etiqueta(UNIDADES, d.quantityUnit)}`,
          [d.destination, d.lotCode].filter((v) => typeof v === 'string' && v).join(' · '),
        ];
      }),
  );
}

function pies(doc: Doc, cuaderno: CuadernoExportado): void {
  const generado = new Date(cuaderno.generatedAt).toLocaleString('es-ES', {
    timeZone: 'Europe/Madrid',
  });
  const origen =
    cuaderno.source === 'snapshot'
      ? 'Campaña cerrada: los datos de la explotación son los guardados al cerrarla.'
      : 'Campaña en curso: los datos son los del momento de generarlo.';
  const rango = doc.bufferedPageRange();

  for (let i = rango.start; i < rango.start + rango.count; i += 1) {
    doc.switchToPage(i);
    // Escribir por debajo del margen inferior hace que PDFKit añada una
    // página nueva y el pie acabe en una hoja en blanco al final. Con el
    // margen a cero mientras se escribe, se queda donde tiene que estar.
    doc.page.margins.bottom = 0;
    doc.font('Helvetica').fontSize(7).fillColor(GRIS);
    doc.text(
      `${cuaderno.campaign.name} · Generado el ${generado} · ${origen} ` +
        'Este documento recoge lo registrado en la plataforma; no es el formulario oficial ' +
        'ni una validación de la normativa aplicable.',
      MARGEN,
      doc.page.height - MARGEN + 2,
      { width: ANCHO_UTIL - 40, align: 'left', lineGap: -1 },
    );
    doc.text(
      `${i - rango.start + 1}/${rango.count}`,
      MARGEN + ANCHO_UTIL - 40,
      doc.page.height - MARGEN + 2,
      { width: 40, align: 'right' },
    );
    doc.page.margins.bottom = MARGEN;
  }
}

function seccionDeResumen(doc: Doc, cuaderno: CuadernoExportado): void {
  const s = cuaderno.summary;
  const lineas: Array<[string, string]> = [
    ['Superficie', `${cifra(cuaderno.campaign.areaHa, 4)} ha`],
    ['Actividades registradas', String(s.activityCount)],
  ];
  if (s.irrigation) {
    lineas.push([
      'Riego',
      `${s.irrigation.count} · ${cifra(s.irrigation.volumeM3, 1)} m³` +
        (s.irrigation.volumeM3PerHa == null
          ? ''
          : ` (${cifra(s.irrigation.volumeM3PerHa, 1)} m³/ha)`) +
        (s.irrigation.withoutVolume > 0 ? ` · ${s.irrigation.withoutVolume} sin cantidad` : ''),
    ]);
  }
  if (s.fertilization) {
    lineas.push([
      'Fertilización',
      `${s.fertilization.count} · N ${cifra(s.fertilization.nKg, 1)} kg · ` +
        `P2O5 ${cifra(s.fertilization.p2o5Kg, 1)} kg · K2O ${cifra(s.fertilization.k2oKg, 1)} kg` +
        (s.fertilization.withoutComposition > 0
          ? ` · ${s.fertilization.withoutComposition} sin riqueza`
          : ''),
    ]);
  }
  if (s.phytosanitary) {
    lineas.push([
      'Tratamientos',
      `${s.phytosanitary.count} · ${s.phytosanitary.distinctProducts} productos distintos`,
    ]);
  }
  if (s.harvest) {
    lineas.push([
      'Recolección',
      `${cifra(s.harvest.quantityKg, 1)} kg` +
        (s.harvest.yieldKgHa == null ? '' : ` · ${cifra(s.harvest.yieldKgHa, 1)} kg/ha`) +
        (s.harvest.withoutKg > 0 ? ` · ${s.harvest.withoutKg} sin cantidad` : ''),
    ]);
  }
  if (s.fieldWork) {
    lineas.push(['Labores', String(s.fieldWork.count)]);
  }
  if (s.observations) {
    lineas.push(['Observaciones', String(s.observations.count)]);
  }
  ficha(doc, lineas);
}

function seccionDePendientes(doc: Doc, cuaderno: CuadernoExportado): void {
  const pendiente = cuaderno.pending;
  if (
    !pendiente ||
    !pendiente.applicable ||
    pendiente.missingCount + pendiente.warningCount === 0
  ) {
    return;
  }
  titulo(doc, 'Información pendiente');
  parrafo(
    doc,
    `Revisado con las reglas ${pendiente.rules.id}. Lo que sigue es información que no está ` +
      'registrada; no es una valoración de si el cuaderno es suficiente para una inspección.',
    true,
  );
  const filas = [
    ...pendiente.campaign.map((a) => ['Campaña', a.label, a.sourceLabel]),
    ...pendiente.activities.flatMap((fila) =>
      fila.items.map((a) => [
        `${etiqueta(TIPOS_DE_ACTIVIDAD, fila.type)} ${fecha(fila.startDate)}`,
        a.label,
        a.sourceLabel,
      ]),
    ),
  ];
  tabla(
    doc,
    [
      { titulo: 'Dónde', ancho: 120 },
      { titulo: 'Qué falta', ancho: 200 },
      { titulo: 'Por qué se pide', ancho: 179 },
    ],
    filas,
  );
}

function cuerpoInforme(doc: Doc, cuaderno: CuadernoExportado): void {
  doc.font('Helvetica-Bold').fontSize(17).fillColor(NEGRO).text('Cuaderno de campo');
  doc.font('Helvetica').fontSize(11).fillColor(GRIS).text(cuaderno.campaign.name);
  doc.fontSize(9).text(periodo(cuaderno));
  doc.moveDown(0.8);

  cabeceraDeLaFinca(doc, cuaderno);
  titulo(doc, 'Resumen de la campaña');
  seccionDeResumen(doc, cuaderno);

  titulo(doc, 'Unidades de cultivo');
  unidadesDeCultivo(doc, cuaderno);

  titulo(doc, 'Lo que se ha hecho');
  tabla(
    doc,
    [
      { titulo: 'Fecha', ancho: 66 },
      { titulo: 'Tipo', ancho: 110 },
      { titulo: 'Parcelas', ancho: 120 },
      { titulo: 'ha', ancho: 40, derecha: true },
      { titulo: 'Detalle', ancho: 163 },
    ],
    cuaderno.activities.map((actividad) => [
      actividad.startDate === actividad.endDate
        ? fecha(actividad.startDate)
        : `${fecha(actividad.startDate)}–${fecha(actividad.endDate)}`,
      etiqueta(TIPOS_DE_ACTIVIDAD, actividad.type),
      actividad.targets.map((t) => t.parcelName).join(', '),
      cifra(actividad.areaHa, 4),
      [resumenDeActividad(actividad), actividad.notes ?? ''].filter(Boolean).join(' — '),
    ]),
  );

  if (cuaderno.activities.some((a) => a.type === 'phytosanitary')) {
    titulo(doc, 'Tratamientos fitosanitarios');
    tablaDeTratamientos(doc, cuaderno);
  }
  if (cuaderno.activities.some((a) => a.type === 'fertilization')) {
    titulo(doc, 'Fertilización');
    tablaDeAbonados(doc, cuaderno);
  }
  if (cuaderno.activities.some((a) => a.type === 'irrigation')) {
    titulo(doc, 'Riego');
    tablaDeRiegos(doc, cuaderno);
  }
  if (cuaderno.activities.some((a) => a.type === 'harvest')) {
    titulo(doc, 'Recolección');
    tablaDeCosechas(doc, cuaderno);
  }
  seccionDePendientes(doc, cuaderno);
}

function cuerpoCue(doc: Doc, cuaderno: CuadernoExportado): void {
  doc.font('Helvetica-Bold').fontSize(17).fillColor(NEGRO).text('Cuaderno de explotación');
  doc.font('Helvetica').fontSize(11).fillColor(GRIS).text(cuaderno.campaign.name);
  doc.fontSize(9).text(periodo(cuaderno));
  doc.moveDown(0.6);
  parrafo(
    doc,
    'Los datos registrados, ordenados por los apartados del Cuaderno Único de Explotación, ' +
      'para poder cotejarlos apartado a apartado. La estructura oficial la fija la ' +
      'Administración y puede cambiar: esto es una presentación de lo registrado, no el ' +
      'formulario oficial.',
    true,
  );

  titulo(doc, '1. Identificación de la explotación');
  cabeceraDeLaFinca(doc, cuaderno);

  titulo(doc, '2. Unidades de cultivo');
  unidadesDeCultivo(doc, cuaderno);

  titulo(doc, '3. Tratamientos fitosanitarios');
  parrafo(
    doc,
    'Producto y número de registro, fecha y hora de inicio, dosis, superficie tratada y estado ' +
      'del cultivo, como pide el Reglamento de Ejecución (UE) 2023/564.',
    true,
  );
  tablaDeTratamientos(doc, cuaderno);

  titulo(doc, '4. Fertilización');
  tablaDeAbonados(doc, cuaderno);

  titulo(doc, '5. Riego');
  tablaDeRiegos(doc, cuaderno);

  titulo(doc, '6. Recolección');
  tablaDeCosechas(doc, cuaderno);

  const labores = cuaderno.activities.filter((a) => a.type === 'field_work');
  if (labores.length > 0) {
    titulo(doc, '7. Labores y otras actuaciones');
    tabla(
      doc,
      [
        { titulo: 'Desde', ancho: 66 },
        { titulo: 'Hasta', ancho: 66 },
        { titulo: 'Parcelas', ancho: 130 },
        { titulo: 'ha', ancho: 40, derecha: true },
        { titulo: 'Labor', ancho: 197 },
      ],
      labores.map((actividad) => [
        fecha(actividad.startDate),
        fecha(actividad.endDate),
        actividad.targets.map((t) => t.parcelName).join(', '),
        cifra(actividad.areaHa, 4),
        [
          etiqueta(TIPOS_DE_LABOR, actividad.fieldWork?.workType),
          typeof actividad.fieldWork?.machinery === 'string' ? actividad.fieldWork.machinery : '',
        ]
          .filter(Boolean)
          .join(' · '),
      ]),
    );
  }
  seccionDePendientes(doc, cuaderno);
}

export function aPdf(
  cuaderno: CuadernoExportado,
  disposicion: DisposicionDelPdf = 'informe',
): Promise<Buffer> {
  const doc = new PDFDocument({
    size: 'A4',
    margins: { top: MARGEN, bottom: MARGEN, left: MARGEN, right: MARGEN },
    bufferPages: true,
    info: {
      Title: `Cuaderno de campo - ${cuaderno.campaign.name}`,
      Author: cuaderno.organization.name ?? 'Plataforma IoT',
      Subject: disposicion === 'cue' ? 'Cuaderno de explotación' : 'Cuaderno de campo',
    },
  });

  const trozos: Buffer[] = [];
  const terminado = new Promise<Buffer>((resolve, reject) => {
    doc.on('data', (trozo: Buffer) => trozos.push(trozo));
    doc.on('end', () => resolve(Buffer.concat(trozos)));
    doc.on('error', reject);
  });

  if (disposicion === 'cue') {
    cuerpoCue(doc, cuaderno);
  } else {
    cuerpoInforme(doc, cuaderno);
  }
  pies(doc, cuaderno);
  doc.end();

  return terminado;
}
