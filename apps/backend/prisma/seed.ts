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
];

// PERMISSIONS.md §14 — catálogo de ejemplo; se amplía a medida que cada
// función V2/Futuro se construye (BACKLOG.md).
const FEATURES = [
  { code: 'reports_pdf', label: 'Informes en PDF' },
  { code: 'campaigns', label: 'Campañas' },
  { code: 'weather_widget', label: 'Pestaña de tiempo/clima' },
  { code: 'satellite_imagery', label: 'Imágenes satelitales' },
  { code: 'recommendations', label: 'Recomendaciones' },
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
