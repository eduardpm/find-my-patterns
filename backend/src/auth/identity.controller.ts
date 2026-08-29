import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  UnauthorizedException,
} from '@nestjs/common';
import { z } from 'zod';
import { EntitlementsService } from '../billing/entitlements.service';
import { parseOrThrow } from '../common/validation';
import { DEFAULT_USER_ID } from './default-user';
import { AuthService, type TokenOut, type UserOut } from './identity.service';
import { extractBearerToken } from './tokens';

/**
 * Whether `GET /auth/me` may answer for the default user with no bearer token at all — mirrors
 * `MANUAL_ENTITLEMENTS` (`../billing/entitlements.controller.ts`)'s per-boot-injection shape.
 *
 * M-3 (#48): before this ticket, `/auth/me` required a real bearer token unconditionally, even
 * under `SINGLE_USER_MODE=true` where every *other* route resolves to `DEFAULT_USER_ID` with none
 * (`../auth/identity.middleware.ts`) — M-1a's own contract test called this "same posture,
 * plumbing only", correctly describing that nothing consumed the new `/auth/*` namespace yet. M-3
 * is the first thing that does: the mobile client's only way to learn its tier is `GET /auth/me`
 * (issue task 2), and the app's documented, shipped default is `SINGLE_USER_MODE=true` with no
 * client sending a bearer token (`main.ts`'s own boot log says exactly this). Leaving `/auth/me`
 * as the one route that still 401s in that mode would make tier permanently unreadable in the
 * product's default configuration — not a deliberate boundary, a gap this ticket is what surfaces.
 */
export const SINGLE_USER_MODE = Symbol('SINGLE_USER_MODE');

/**
 * Multi-tenant identity endpoints (M-1a, #45).
 *
 * Deliberately **not** `/auth/login` and `/auth/logout` — those paths already belong to the
 * existing single-password `AuthManager` (`./auth.ts`), registered directly on the Express app
 * when `AUTH_ENABLED=true`. Nest binds its own controller routes before `AuthManager.install` runs
 * (`main.ts`), so if this controller answered the same path, Nest's JSON handler would always
 * intercept the request first and `AuthManager`'s HTML form/cookie flow would silently stop firing
 * the moment both features were ever enabled together — exactly the regression "keep cookies
 * working" (the recon's phrase) rules out. `register` / `token` / `me` are a disjoint namespace
 * from that flow, from `/auth/status`, and from the mobile app's currently-unused `/auth/session`
 * placeholder (`mobile/lib/core/config/app_config.dart` — dead code today, `requireAuth` is
 * `false`), so nothing collides regardless of which flags are set.
 *
 * A bearer token is a resource here: `POST /auth/token` creates one (logs in), `DELETE /auth/token`
 * destroys the one presented (logs out) — REST-y, and it reads correctly either way.
 */

const credentialsSchema = z.object({
  email: z.string().trim().toLowerCase().email('expected a valid email address').max(256),
  // `hashPassword` (`./password.ts`) already refuses anything under 12 characters; checked again
  // here so a too-short password answers 422 with a field-level message instead of a 500 raised
  // from inside the hashing call.
  password: z.string().min(12, 'must be at least 12 characters').max(256),
});

/**
 * `GET /auth/me`'s response, extended for M-2 (#47) with the caller's entitlement state. A separate
 * interface from `UserOut` rather than adding these fields to it directly: `register` and `login`
 * both return `UserOut` too, and neither has any business reporting a tier — `register` runs before
 * an account can hold one, and `login`'s job is issuing a session token, not describing account
 * state. Keeping `UserOut` unchanged means neither of those two response shapes moves.
 */
export interface MeOut extends UserOut {
  tier: 'free' | 'premium';
  /** The entitlement's own expiry (`EntitlementsService`'s `EntitlementOut`), `null` for free or
   * for a lifetime purchase. Not to be confused with `TokenOut.expires_at` above, which is when the
   * bearer *session* stops working — two different clocks that happen to share a field name because
   * both are "when does this stop being true," on two unrelated things. */
  expires_at: string | null;
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly entitlements: EntitlementsService,
    @Inject(SINGLE_USER_MODE) private readonly singleUserMode: boolean,
  ) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  register(@Body() body: unknown): Promise<UserOut> {
    const { email, password } = parseOrThrow(credentialsSchema, body);
    return this.auth.register(email, password);
  }

  @Post('token')
  @HttpCode(HttpStatus.OK)
  login(@Body() body: unknown): Promise<TokenOut> {
    const { email, password } = parseOrThrow(credentialsSchema, body);
    return this.auth.login(email, password);
  }

  @Delete('token')
  @HttpCode(HttpStatus.NO_CONTENT)
  logout(@Headers('authorization') authorization?: string): void {
    const token = extractBearerToken(authorization);
    // No token, or one that never resolves: still a 204. See `AuthService.logout`'s doc comment —
    // "logged out" is the correct end state whether or not the token was ever valid.
    if (token) this.auth.logout(token);
  }

  @Get('me')
  async me(@Headers('authorization') authorization?: string): Promise<MeOut> {
    const token = extractBearerToken(authorization);
    let user: UserOut;
    if (token) {
      user = await this.auth.me(token);
    } else if (this.singleUserMode) {
      // See `SINGLE_USER_MODE`'s doc comment above: no client in the app's default configuration
      // ever sends a bearer token, so falling through to 401 here would make tier permanently
      // unreadable rather than merely "not yet wired up". `ensureDefaultUser` (`./default-user.ts`)
      // guarantees this row exists on any diary this backend can boot against, so `byId` returning
      // `null` here would mean a corrupted install, not a normal miss — surfacing that as the
      // ordinary "no token" 401 would misreport what actually went wrong, so it is left to throw.
      const defaultUser = this.auth.byId(DEFAULT_USER_ID);
      if (!defaultUser) throw new UnauthorizedException('A bearer token is required.');
      user = defaultUser;
    } else {
      throw new UnauthorizedException('A bearer token is required.');
    }
    const entitlement = this.entitlements.getEntitlement(user.id);
    return { ...user, ...entitlement };
  }
}
