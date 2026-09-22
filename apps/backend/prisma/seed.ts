/**
 * Semilla de catálogos de plataforma (DATA_MODEL.md) + bootstrap del primer
 * Admin de plataforma (DEPLOYMENT.md §3, `PLATFORM_ADMIN_BOOTSTRAP_EMAIL`).
 * Ejecutar con `npm run prisma:seed` tras aplicar las migraciones.
 */
import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

const ROLES = [
  { code: 'org_admin', label: 'Administrador de organización' },
  { code: 'technician', label: 'Técnico' },
  { code: 'operator', label: 'Operador' },
  { code: 'read_only', label: 'Solo lectura' },
];

// FUNCTIONAL_REQUIREMENTS.md §8, DATA_MODEL.md — catálogo inicial, ampliable
// sin cambios estructurales.
const CHANNEL_TYPES = [
  { code: 'temperature_air', unit: '°C', dataType: 'continuous', defaultAggregation: 'average', minValid: -40, maxValid: 60 },
  { code: 'humidity_air', unit: '%', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 100 },
  { code: 'humidity_soil', unit: '%', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 100 },
  { code: 'conductivity', unit: 'µS/cm', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 20000 },
  { code: 'tank_level', unit: '%', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 100 },
  { code: 'battery', unit: '%', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 100 },
  { code: 'signal_strength', unit: 'dBm', dataType: 'continuous', defaultAggregation: 'average', minValid: -120, maxValid: 0 },
  { code: 'precipitation', unit: 'mm', dataType: 'counter', defaultAggregation: 'sum', minValid: 0, maxValid: 500 },
  // Estación WSC2-N con sondas de suelo (BACKLOG.md #44): la temperatura de
  // las sondas de suelo y la succión del tensiómetro, en centibares (1 cb =
  // 1 kPa; 0 = suelo saturado). El mínimo admite -10 cb porque al aire el
  // tensiómetro marca alrededor de 0 y su cero deriva un poco.
  { code: 'temperature_soil', unit: '°C', dataType: 'continuous', defaultAggregation: 'average', minValid: -40, maxValid: 80 },
  { code: 'tension_soil', unit: 'cb', dataType: 'continuous', defaultAggregation: 'average', minValid: -10, maxValid: 100 },
  // Estado de la propia estación (BACKLOG.md #49, mejora F): el puente manda en
  // cada envío la tensión de su batería, en voltios (la WSC2-N no da porcentaje),
  // junto con la cobertura en dBm. Así la plataforma sabe que la estación está
  // viva aunque no lleguen datos de sus sensores.
  { code: 'battery_voltage', unit: 'V', dataType: 'continuous', defaultAggregation: 'average', minValid: 0, maxValid: 15 },
];

// PERMISSIONS.md §14 — catálogo de ejemplo; se amplía a medida que cada
// función V2/Futuro se construye (BACKLOG.md).
const FEATURES = [
  { code: 'reports_pdf', label: 'Informes en PDF' },
  { code: 'campaigns', label: 'Campañas' },
  { code: 'weather_widget', label: 'Pestaña de tiempo/clima' },
  { code: 'satellite_imagery', label: 'Imágenes satelitales' },
  { code: 'recommendations', label: 'Recomendaciones' },
  { code: 'disease_risk', label: 'Afecciones y patógenos' },
];

// Catálogo de cultivos (migración 0010, BACKLOG.md #60). El agricultor elige
// de esta lista en vez de escribir el nombre, para que el día que se importen
// los catálogos oficiales (EPPO, catálogo de productos del SIEX) se puedan
// mapear sin reescribir los datos de nadie. Solo nombres y categoría: los
// códigos oficiales se rellenan al importarlos, nunca a ojo. Lo que no esté
// aquí se escribe a mano en la campaña ("otro cultivo").
//
// El `id` es estable: no se cambia aunque se retoque el nombre.
const CROPS: Array<{ id: string; name: string; category: string }> = [
  // Leñosos
  { id: 'aguacate', name: 'Aguacate', category: 'woody' },
  { id: 'albaricoquero', name: 'Albaricoquero', category: 'woody' },
  { id: 'algarrobo', name: 'Algarrobo', category: 'woody' },
  { id: 'almendro', name: 'Almendro', category: 'woody' },
  { id: 'avellano', name: 'Avellano', category: 'woody' },
  { id: 'caqui', name: 'Caqui', category: 'woody' },
  { id: 'cerezo', name: 'Cerezo', category: 'woody' },
  { id: 'chirimoyo', name: 'Chirimoyo', category: 'woody' },
  { id: 'ciruelo', name: 'Ciruelo', category: 'woody' },
  { id: 'granado', name: 'Granado', category: 'woody' },
  { id: 'higuera', name: 'Higuera', category: 'woody' },
  { id: 'kiwi', name: 'Kiwi', category: 'woody' },
  { id: 'limonero', name: 'Limonero', category: 'woody' },
  { id: 'mandarino', name: 'Mandarino', category: 'woody' },
  { id: 'mango', name: 'Mango', category: 'woody' },
  { id: 'manzano', name: 'Manzano', category: 'woody' },
  { id: 'melocotonero', name: 'Melocotonero', category: 'woody' },
  { id: 'naranjo', name: 'Naranjo', category: 'woody' },
  { id: 'nectarino', name: 'Nectarino', category: 'woody' },
  { id: 'nispero', name: 'Níspero', category: 'woody' },
  { id: 'nogal', name: 'Nogal', category: 'woody' },
  { id: 'olivo', name: 'Olivo', category: 'woody' },
  { id: 'peral', name: 'Peral', category: 'woody' },
  { id: 'pistachero', name: 'Pistachero', category: 'woody' },
  { id: 'pomelo', name: 'Pomelo', category: 'woody' },
  { id: 'vid_mesa', name: 'Vid (uva de mesa)', category: 'woody' },
  { id: 'vid_vinificacion', name: 'Vid (uva de vinificación)', category: 'woody' },
  // Herbáceos extensivos
  { id: 'alfalfa', name: 'Alfalfa', category: 'forage' },
  { id: 'algodon', name: 'Algodón', category: 'herbaceous' },
  { id: 'arroz', name: 'Arroz', category: 'herbaceous' },
  { id: 'avena', name: 'Avena', category: 'herbaceous' },
  { id: 'cebada', name: 'Cebada', category: 'herbaceous' },
  { id: 'centeno', name: 'Centeno', category: 'herbaceous' },
  { id: 'colza', name: 'Colza', category: 'herbaceous' },
  { id: 'garbanzo', name: 'Garbanzo', category: 'herbaceous' },
  { id: 'girasol', name: 'Girasol', category: 'herbaceous' },
  { id: 'guisante', name: 'Guisante', category: 'herbaceous' },
  { id: 'haba', name: 'Haba', category: 'herbaceous' },
  { id: 'lenteja', name: 'Lenteja', category: 'herbaceous' },
  { id: 'maiz', name: 'Maíz', category: 'herbaceous' },
  { id: 'remolacha_azucarera', name: 'Remolacha azucarera', category: 'herbaceous' },
  { id: 'trigo_blando', name: 'Trigo blando', category: 'herbaceous' },
  { id: 'trigo_duro', name: 'Trigo duro', category: 'herbaceous' },
  { id: 'pastos', name: 'Pastos y praderas', category: 'forage' },
  // Hortícolas
  { id: 'ajo', name: 'Ajo', category: 'horticultural' },
  { id: 'alcachofa', name: 'Alcachofa', category: 'horticultural' },
  { id: 'berenjena', name: 'Berenjena', category: 'horticultural' },
  { id: 'brocoli', name: 'Brócoli', category: 'horticultural' },
  { id: 'calabacin', name: 'Calabacín', category: 'horticultural' },
  { id: 'cebolla', name: 'Cebolla', category: 'horticultural' },
  { id: 'col', name: 'Col', category: 'horticultural' },
  { id: 'coliflor', name: 'Coliflor', category: 'horticultural' },
  { id: 'esparrago', name: 'Espárrago', category: 'horticultural' },
  { id: 'fresa', name: 'Fresa', category: 'horticultural' },
  { id: 'judia_verde', name: 'Judía verde', category: 'horticultural' },
  { id: 'lechuga', name: 'Lechuga', category: 'horticultural' },
  { id: 'melon', name: 'Melón', category: 'horticultural' },
  { id: 'patata', name: 'Patata', category: 'horticultural' },
  { id: 'pepino', name: 'Pepino', category: 'horticultural' },
  { id: 'pimiento', name: 'Pimiento', category: 'horticultural' },
  { id: 'sandia', name: 'Sandía', category: 'horticultural' },
  { id: 'tomate', name: 'Tomate', category: 'horticultural' },
  { id: 'zanahoria', name: 'Zanahoria', category: 'horticultural' },
];

async function main(): Promise<void> {
  for (const role of ROLES) {
    await prisma.role.upsert({ where: { code: role.code }, update: role, create: role });
  }

  for (const channelType of CHANNEL_TYPES) {
    await prisma.channelType.upsert({
      where: { code: channelType.code },
      update: channelType as never,
      create: channelType as never,
    });
  }

  for (const feature of FEATURES) {
    await prisma.feature.upsert({ where: { code: feature.code }, update: feature, create: feature });
  }

  // Solo nombre y categoría: si algún día se rellenan los códigos oficiales
  // al importar un catálogo, el seed no los pisa.
  for (const crop of CROPS) {
    await prisma.crop.upsert({
      where: { id: crop.id },
      update: { name: crop.name, category: crop.category },
      create: crop,
    });
  }

  const bootstrapEmail = process.env.PLATFORM_ADMIN_BOOTSTRAP_EMAIL;
  const bootstrapPassword = process.env.PLATFORM_ADMIN_BOOTSTRAP_PASSWORD;
  if (bootstrapEmail && bootstrapPassword) {
    const existing = await prisma.user.findUnique({ where: { email: bootstrapEmail } });
    const user =
      existing ??
      (await prisma.user.create({
        data: {
          email: bootstrapEmail,
          fullName: 'Platform Admin',
          passwordHash: await argon2.hash(bootstrapPassword, { type: argon2.argon2id }),
        },
      }));
    await prisma.platformAdmin.upsert({
      where: { userId: user.id },
      update: {},
      create: { userId: user.id },
    });
    // eslint-disable-next-line no-console
    console.log(`Platform admin ready: ${bootstrapEmail}`);
  } else {
    // eslint-disable-next-line no-console
    console.log('PLATFORM_ADMIN_BOOTSTRAP_EMAIL/PASSWORD not set — skipping platform admin bootstrap.');
  }
}

main()
  .catch((error) => {
    // eslint-disable-next-line no-console
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
