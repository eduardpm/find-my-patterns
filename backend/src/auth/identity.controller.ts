import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  UnauthorizedException,
} from '@nestjs/common';
import { z } from 'zod';
import { parseOrThrow } from '../common/validation';
import { AuthService, type TokenOut, type UserOut } from './identity.service';
import { extractBearerToken } from './tokens';

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

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

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
  me(@Headers('authorization') authorization?: string): Promise<UserOut> {
    const token = extractBearerToken(authorization);
    if (!token) throw new UnauthorizedException('A bearer token is required.');
    return this.auth.me(token);
  }
}
