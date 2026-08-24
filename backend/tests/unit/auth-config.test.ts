import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadAuthConfig } from '../../src/config';

afterEach(() => vi.unstubAllEnvs());

describe('authentication configuration', () => {
  it('is safely disabled by default', () => {
    vi.stubEnv('AUTH_ENABLED', 'false');
    expect(loadAuthConfig()).toMatchObject({ enabled: false, secureCookie: false });
  });

  it('fails closed when enabled credentials are incomplete', () => {
    vi.stubEnv('AUTH_ENABLED', 'true');
    vi.stubEnv('AUTH_EMAIL', '');
    vi.stubEnv('AUTH_PASSWORD_HASH', '');
    expect(() => loadAuthConfig()).toThrow(/Refusing to start unprotected/);
  });

  it('defaults enabled deployments to Secure cookies', () => {
    vi.stubEnv('AUTH_ENABLED', 'true');
    vi.stubEnv('AUTH_EMAIL', 'OWNER@EXAMPLE.COM');
    vi.stubEnv('AUTH_PASSWORD_HASH', 'configured-hash');
    expect(loadAuthConfig()).toMatchObject({
      enabled: true,
      email: 'owner@example.com',
      secureCookie: true,
    });
  });
});
