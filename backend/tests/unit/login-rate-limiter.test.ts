/**
 * The login throttle's reset/expiry path (task 5, M-1a, #45) — tested with an injected clock
 * rather than a real 15-minute wait, per the recon's instruction that this be "testable (inject
 * the clock or the counter ... so the expired/reset path can be tested deterministically)".
 */

import { describe, expect, it } from 'vitest';
import { LoginRateLimiter } from '../../src/auth/login-rate-limiter';

describe('LoginRateLimiter', () => {
  it('blocks once the failure count reaches the limit', () => {
    const limiter = new LoginRateLimiter({ maxAttempts: 3, windowMs: 1000 });
    expect(limiter.isBlocked('a@example.com')).toBe(false);
    limiter.recordFailure('a@example.com');
    limiter.recordFailure('a@example.com');
    expect(limiter.isBlocked('a@example.com')).toBe(false);
    limiter.recordFailure('a@example.com');
    expect(limiter.isBlocked('a@example.com')).toBe(true);
  });

  it('tracks each email independently — one under attack does not lock out another', () => {
    const limiter = new LoginRateLimiter({ maxAttempts: 1, windowMs: 1000 });
    limiter.recordFailure('victim@example.com');
    expect(limiter.isBlocked('victim@example.com')).toBe(true);
    expect(limiter.isBlocked('someone-else@example.com')).toBe(false);
  });

  it('un-blocks once the window has passed, without waiting for real time', () => {
    let now = 0;
    const limiter = new LoginRateLimiter({ maxAttempts: 1, windowMs: 1000, now: () => now });

    limiter.recordFailure('a@example.com');
    expect(limiter.isBlocked('a@example.com')).toBe(true);

    now = 999;
    expect(limiter.isBlocked('a@example.com')).toBe(true);

    now = 1001;
    expect(limiter.isBlocked('a@example.com')).toBe(false);
  });

  it('reset clears the count immediately, for a successful login after prior failures', () => {
    const limiter = new LoginRateLimiter({ maxAttempts: 1, windowMs: 1000 });
    limiter.recordFailure('a@example.com');
    expect(limiter.isBlocked('a@example.com')).toBe(true);

    limiter.reset('a@example.com');
    expect(limiter.isBlocked('a@example.com')).toBe(false);
  });
});
