/**
 * `RequiresPremiumGuard` (M-2, #47, issue task 4): unit-tested directly against a mocked
 * `ExecutionContext`, exactly as its own doc comment says, since it is applied to no route in this
 * PR — gating which features require premium is M-3's decision, not this ticket's. This is what
 * proves the primitive works despite having no real caller yet.
 */

import type { ExecutionContext } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { EntitlementsService } from '../../src/billing/entitlements.service';
import {
  PremiumRequiredException,
  RequiresPremiumGuard,
} from '../../src/billing/requires-premium.guard';
import type { DiaryDatabase } from '../../src/db/database';

/** A fake `EntitlementsService` is unnecessary — a real one backed by a tiny fake `DiaryDatabase`
 * is simpler here, since all the guard needs from it is `getEntitlement`'s return value, and
 * stubbing one SQL call is less code than mocking the class. */
function serviceReturning(tier: 'free' | 'premium'): EntitlementsService {
  const fakeDb = {
    prepare: () => ({
      get: () => (tier === 'free' ? undefined : { tier: 'premium', expires_at: null }),
    }),
  } as unknown as DiaryDatabase;
  return new EntitlementsService(fakeDb);
}

function contextFor(userId: string | undefined): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => ({ userId }),
    }),
  } as unknown as ExecutionContext;
}

describe('RequiresPremiumGuard', () => {
  it('blocks a free user with PremiumRequiredException', () => {
    const guard = new RequiresPremiumGuard(serviceReturning('free'));
    expect(() => guard.canActivate(contextFor('user-1'))).toThrow(PremiumRequiredException);
  });

  it('allows a premium user through', () => {
    const guard = new RequiresPremiumGuard(serviceReturning('premium'));
    expect(guard.canActivate(contextFor('user-1'))).toBe(true);
  });

  it('fails closed when req.userId is somehow missing', () => {
    const guard = new RequiresPremiumGuard(serviceReturning('premium'));
    expect(() => guard.canActivate(contextFor(undefined))).toThrow(PremiumRequiredException);
  });
});

describe('PremiumRequiredException', () => {
  it('carries the exact structured body the issue specifies, at 402', () => {
    const error = new PremiumRequiredException();
    expect(error.getStatus()).toBe(402);
    expect(error.getResponse()).toEqual({ error: 'premium_required' });
  });
});
