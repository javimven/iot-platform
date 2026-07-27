import { generateOpaqueSecret, hashOpaqueSecret, verifyOpaqueSecret } from './opaque-secret.util';

describe('opaque-secret.util (DATA_MODEL.md §3 — sesiones)', () => {
  it('genera secretos distintos en cada llamada', () => {
    expect(generateOpaqueSecret()).not.toBe(generateOpaqueSecret());
  });

  it('verifica correctamente un secreto contra su propio hash', () => {
    const secret = generateOpaqueSecret();
    const hash = hashOpaqueSecret(secret);
    expect(verifyOpaqueSecret(hash, secret)).toBe(true);
  });

  it('rechaza un secreto incorrecto', () => {
    const hash = hashOpaqueSecret(generateOpaqueSecret());
    expect(verifyOpaqueSecret(hash, 'not-the-secret')).toBe(false);
  });
});
