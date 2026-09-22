import { IsBoolean, IsOptional } from 'class-validator';

/**
 * Perfil del cuaderno completo (ADR-0013): las preguntas que el sistema no
 * puede deducir, y de las que depende qué secciones se enseñan. Lo que ya se
 * sabe no se pregunta: si el cultivo es de regadío lo dice la unidad de
 * cultivo, y si la producción es ecológica o integrada, también.
 *
 * Se guarda como JSON (`campaigns.notebook_profile`) porque es configuración y
 * sus preguntas cambiarán con la normativa, pero solo entra lo que está aquí:
 * el `ValidationPipe` global rechaza cualquier otra clave.
 */
export class NotebookProfileDto {
  @IsOptional()
  @IsBoolean()
  usesPlantProtectionProducts?: boolean;

  @IsOptional()
  @IsBoolean()
  appliesFertilizers?: boolean;

  @IsOptional()
  @IsBoolean()
  usesFertigation?: boolean;

  @IsOptional()
  @IsBoolean()
  participatesInEcoSchemes?: boolean;

  @IsOptional()
  @IsBoolean()
  usesValorizableWaste?: boolean;

  @IsOptional()
  @IsBoolean()
  postHarvestTreatments?: boolean;

  @IsOptional()
  @IsBoolean()
  storageTreatments?: boolean;

  @IsOptional()
  @IsBoolean()
  transportTreatments?: boolean;

  @IsOptional()
  @IsBoolean()
  treatedSeed?: boolean;
}

/**
 * Versión del formato del perfil guardado. Si cambian las preguntas, sube, y
 * se sabe con qué preguntas se respondió cada perfil.
 */
export const VERSION_PERFIL = 1;

export function perfilParaGuardar(perfil: NotebookProfileDto | undefined): Record<string, unknown> {
  const respuestas = Object.fromEntries(
    Object.entries(perfil ?? {}).filter(([, valor]) => typeof valor === 'boolean'),
  );
  return { version: VERSION_PERFIL, ...respuestas };
}
