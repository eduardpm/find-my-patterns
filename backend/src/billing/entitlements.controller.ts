import {
  BadGatewayException,
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Inject,
  NotFoundException,
  Post,
  Req,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { parseOrThrow } from '../common/validation';
import { EntitlementsService, type EntitlementOut } from './entitlements.service';
import {
  encodeEpochMillis,
  GooglePlayVerificationError,
  type PlayPurchaseVerifier,
} from './play-verifier';

export const PLAY_VERIFIER = Symbol('PLAY_VERIFIER');
/** Whether `POST /billing/admin/grant` (the issue's task 6 "admin escape hatch") answers at all —
 * see that handler's doc comment for why it shares its gate with the verify endpoint's dev bypass
 * instead of having its own env var. */
export const MANUAL_ENTITLEMENTS = Symbol('MANUAL_ENTITLEMENTS');

const verifySchema = z.object({
  purchase_token: z.string().trim().min(1),
  product_id: z.string().trim().min(1),
  product_type: z.enum(['subscription', 'onetime']).default('subscription'),
});

const adminGrantSchema = z.object({
  user_id: z.string().trim().min(1),
  tier: z.enum(['free', 'premium']),
  // ISO-8601 wire format for this one admin-only field — everywhere else a client sends a datetime
  // to this API is nowhere, which is exactly why there is no existing convention to match; ISO-8601
  // is what `Date` parses natively, so no bespoke format needs documenting for a dev-only endpoint.
  expires_at: z.string().datetime().nullish(),
});

/**
 * `POST /billing/play/verify` and the dev-only admin grant (issue tasks 2 and 6).
 *
 * `PLAY_VERIFIER` is injected as a token, not a concrete class, so `AppModule` can bind it to
 * `GooglePlayVerifier`, `ManualPlayVerifier`, or (in tests) a `FakePlayVerifier` without this
 * controller ever importing a concrete implementation — see `app.module.ts`'s provider factory for
 * how `MANUAL_ENTITLEMENTS` picks between the first two.
 */
@Controller('billing')
export class EntitlementsController {
  constructor(
    private readonly entitlements: EntitlementsService,
    @Inject(PLAY_VERIFIER) private readonly verifier: PlayPurchaseVerifier,
    @Inject(MANUAL_ENTITLEMENTS) private readonly manualEntitlements: boolean,
  ) {}

  @Post('play/verify')
  @HttpCode(HttpStatus.OK)
  async verify(@Req() req: Request, @Body() body: unknown): Promise<EntitlementOut> {
    const input = parseOrThrow(verifySchema, body);
    // `IdentityGate` (`../auth/identity.middleware.ts`) guarantees `req.userId` on every route it
    // does not exempt, and `/billing/*` is not in its exempt list — this is not a defensive
    // fallback, it documents that guarantee at the one point this controller depends on it.
    const userId = req.userId as string;

    let result;
    try {
      result = await this.verifier.verify(
        input.purchase_token,
        input.product_id,
        input.product_type,
      );
    } catch (error) {
      if (error instanceof GooglePlayVerificationError) {
        // The question could not be asked (Google outage, bad credentials) — distinct from Play
        // answering "no," which the branch below turns into a 422. See `GooglePlayVerificationError`'s
        // own doc comment for why conflating the two would be dangerous.
        throw new BadGatewayException('Could not reach Google Play to verify this purchase.');
      }
      throw error;
    }

    if (!result.valid) {
      throw new UnprocessableEntityException('This purchase token could not be verified.');
    }

    // `MANUAL_ENTITLEMENTS=true` swaps in `ManualPlayVerifier` (`app.module.ts`), which always
    // reports `valid: true` for any token — the resulting grant is recorded as `'manual'`, not
    // `'play'`, so the `entitlements` table itself always tells a real verified purchase apart from
    // a dev bypass, regardless of which endpoint produced it.
    const source = this.manualEntitlements ? 'manual' : 'play';
    return this.entitlements.grant(userId, 'premium', source, result.expiresAt);
  }

  /**
   * Issue task 6: "a small script/endpoint (dev-only) to grant manual entitlements for testing."
   * An endpoint, not a separate script, because it is then automatically exercised by the same
   * e2e/curl walkthrough as everything else, and it needs the same `DIARY_DB` connection the rest
   * of the app already holds open rather than opening a second one.
   *
   * Gated behind `MANUAL_ENTITLEMENTS=true` — the same flag that swaps the verify endpoint over to
   * `ManualPlayVerifier` — rather than a separate env var, because both exist for one reason: make
   * the whole entitlements feature exercisable with zero Google setup (recon acceptance criterion
   * 4). A production deployment that never sets this flag never gets this route at all: it answers
   * 404, not 403, so its existence is not even revealed to an unauthenticated prober.
   *
   * Unlike `verify`, this can target *any* user id, not just the caller's own — the whole point is
   * letting a developer or a test set up a second account's tier directly, which is also why it is
   * the tool this ticket's own e2e suite uses to test the sweep and lifetime-expiry paths without
   * going through the verifier at all.
   */
  @Post('admin/grant')
  @HttpCode(HttpStatus.OK)
  adminGrant(@Body() body: unknown): EntitlementOut {
    if (!this.manualEntitlements) {
      throw new NotFoundException();
    }
    const input = parseOrThrow(adminGrantSchema, body);
    const expiresAt =
      input.tier === 'free'
        ? null // a free entitlement's expiry is meaningless — `getEntitlement` never reads it.
        : input.expires_at
          ? encodeEpochMillis(Date.parse(input.expires_at))
          : null;
    return this.entitlements.grant(input.user_id, input.tier, 'manual', expiresAt);
  }
}
