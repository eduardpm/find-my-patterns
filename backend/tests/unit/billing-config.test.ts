import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadBillingConfig } from '../../src/config';

afterEach(() => vi.unstubAllEnvs());

describe('billing configuration (M-2, #47)', () => {
  it('defaults to manual entitlements off and no Google Play credentials', () => {
    expect(loadBillingConfig()).toMatchObject({
      manualEntitlements: false,
      googlePlay: undefined,
    });
  });

  it('never fails to load over missing Google Play credentials, even with manual entitlements off', () => {
    // See `loadBillingConfig`'s own doc comment: a fresh deployment with no Play integration wired
    // up yet must still boot. The failure — if any — belongs to the first real verify call.
    expect(() => loadBillingConfig()).not.toThrow();
  });

  it('builds googlePlay only once all three fields are present', () => {
    vi.stubEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL', 'svc@project.iam.gserviceaccount.com');
    vi.stubEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_KEY', 'partial-key-only');
    expect(loadBillingConfig().googlePlay).toBeUndefined();

    vi.stubEnv('GOOGLE_PLAY_PACKAGE_NAME', 'org.example.diary');
    expect(loadBillingConfig().googlePlay).toEqual({
      serviceAccountEmail: 'svc@project.iam.gserviceaccount.com',
      privateKey: 'partial-key-only',
      packageName: 'org.example.diary',
    });
  });

  it('unescapes literal \\n sequences in the private key, without touching a real newline', () => {
    vi.stubEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL', 'svc@project.iam.gserviceaccount.com');
    vi.stubEnv(
      'GOOGLE_PLAY_SERVICE_ACCOUNT_KEY',
      '-----BEGIN PRIVATE KEY-----\\nMIIBVgIBADANBg\\n-----END PRIVATE KEY-----\\n',
    );
    vi.stubEnv('GOOGLE_PLAY_PACKAGE_NAME', 'org.example.diary');
    expect(loadBillingConfig().googlePlay?.privateKey).toBe(
      '-----BEGIN PRIVATE KEY-----\nMIIBVgIBADANBg\n-----END PRIVATE KEY-----\n',
    );
  });

  it('parses MANUAL_ENTITLEMENTS as a strict boolean', () => {
    vi.stubEnv('MANUAL_ENTITLEMENTS', 'true');
    expect(loadBillingConfig().manualEntitlements).toBe(true);

    vi.stubEnv('MANUAL_ENTITLEMENTS', 'yes');
    expect(() => loadBillingConfig()).toThrow(/must be either "true" or "false"/);
  });

  it('rejects a sweep interval under one minute', () => {
    vi.stubEnv('ENTITLEMENTS_SWEEP_INTERVAL_MS', '1000');
    expect(() => loadBillingConfig()).toThrow(/ENTITLEMENTS_SWEEP_INTERVAL_MS/);
  });

  it('defaults the sweep interval to once a day', () => {
    expect(loadBillingConfig().entitlementsSweepIntervalMs).toBe(24 * 60 * 60 * 1000);
  });
});
