import { describe, expect, it } from 'vitest';
import { hashPassword, verifyPassword } from '../../src/auth/password';

describe('password hashing', () => {
  it('creates salted scrypt hashes and verifies only the original password', async () => {
    const first = await hashPassword('a long private passphrase');
    const second = await hashPassword('a long private passphrase');

    expect(first).toMatch(/^scrypt\$16384\$8\$1\$/);
    expect(second).not.toBe(first);
    await expect(verifyPassword('a long private passphrase', first)).resolves.toBe(true);
    await expect(verifyPassword('something else entirely', first)).resolves.toBe(false);
  });

  it('rejects weak input and malformed or unsupported hashes', async () => {
    await expect(hashPassword('short')).rejects.toThrow(/12 characters/);
    await expect(verifyPassword('anything', 'not-a-hash')).resolves.toBe(false);
    await expect(verifyPassword('anything', 'scrypt$999999$8$1$c2FsdA$a2V5')).resolves.toBe(false);
  });
});
