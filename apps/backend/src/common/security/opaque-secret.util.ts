import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Secretos opacos de alta entropía (secreto de sesión/refresh, credencial de
 * gateway) — a diferencia de una contraseña de usuario, no hace falta Argon2id
 * (pensado para resistir *baja* entropía/diccionario): un hash rápido
 * (SHA-256) ya es suficiente y evita coste de CPU innecesario en cada refresh
 * (DATA_MODEL.md §3, diseño de sesión).
 */
export function generateOpaqueSecret(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

export function hashOpaqueSecret(secret: string): string {
  return createHash('sha256').update(secret).digest('hex');
}

export function verifyOpaqueSecret(hash: string, candidate: string): boolean {
  const candidateHash = Buffer.from(hashOpaqueSecret(candidate), 'hex');
  const storedHash = Buffer.from(hash, 'hex');
  if (candidateHash.length !== storedHash.length) {
    return false;
  }
  return timingSafeEqual(candidateHash, storedHash);
}
