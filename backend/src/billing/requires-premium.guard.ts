import {
  applyDecorators,
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { EntitlementsService } from './entitlements.service';

/**
 * `requiresPremium`'s structured body (issue task 4): `{"error": "premium_required"}`, a bare
 * string under `error` — deliberately **not** the rest of this API's `{"error": {"code",
 * "message"}}` envelope (`common/http-exception.filter.ts`). The issue names this exact shape as
 * the acceptance criterion, and `ErrorEnvelopeFilter` special-cases it (see that file's comment on
 * `passesThroughAsIs`) rather than reshaping it, so a client can match on the literal string
 * without the extra nesting every other error code carries.
 *
 * 402 Payment Required over 403: the issue allows either, and 402 is the status code whose stated
 * meaning ("payment is required to access this resource") is exactly this condition, not merely a
 * closer approximation of it the way 403 ("forbidden") would be.
 */
export class PremiumRequiredException extends HttpException {
  constructor() {
    super({ error: 'premium_required' }, HttpStatus.PAYMENT_REQUIRED);
  }
}

/**
 * The guard primitive the issue's task 4 asks for, applied to nothing yet — gating *which* routes
 * require premium is explicitly M-3's decision (issue "Out of scope"), not this ticket's. Its own
 * unit test (`tests/unit/requires-premium-guard.test.ts`) is what proves it works despite having no
 * caller in this PR: free → blocked, premium → allowed, unit-tested directly against a mocked
 * `ExecutionContext` rather than through any real route.
 *
 * Reads `req.userId`, set by `IdentityGate` (`../auth/identity.middleware.ts`) on every request
 * that reaches a controller — this guard runs after that middleware in Nest's pipeline, so
 * `req.userId` is always present by the time `canActivate` executes, whether `SINGLE_USER_MODE` is
 * on (every request is the fixed default user) or off (a real bearer token was required to get
 * this far). Delegates the actual "is this premium" question to
 * `EntitlementsService.getEntitlement`, the same live-expiry-checking logic `GET /auth/me` and the
 * sweep both use, so a route this guard protects can never disagree with what `GET /auth/me`
 * reported the client a moment earlier.
 */
@Injectable()
export class RequiresPremiumGuard implements CanActivate {
  constructor(private readonly entitlements: EntitlementsService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const userId = request.userId;
    // `IdentityGate` either sets `req.userId` or ends the request with 401 itself before any guard
    // runs (see `request-identity.d.ts`), so a missing value here would mean this guard was reached
    // on an exempt path (`/health`, `/auth/*`) — not a real usage, but failing closed rather than
    // throwing a TypeError on `undefined` is the safer response to a future routing mistake.
    if (!userId) throw new PremiumRequiredException();

    const { tier } = this.entitlements.getEntitlement(userId);
    if (tier !== 'premium') throw new PremiumRequiredException();
    return true;
  }
}

/** Shorthand for `@UseGuards(RequiresPremiumGuard)` — the "route decorator" half of the issue's
 * "decorator/middleware" phrasing. Usage (once a future ticket actually gates something):
 * `@RequiresPremium() @Get('some-premium-feature') handler() { ... }`. */
export function RequiresPremium(): MethodDecorator & ClassDecorator {
  return applyDecorators(UseGuards(RequiresPremiumGuard));
}
