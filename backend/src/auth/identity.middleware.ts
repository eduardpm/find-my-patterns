import type { NestExpressApplication } from '@nestjs/platform-express';
import express, { type NextFunction, type Request, type Response } from 'express';
import { DEFAULT_USER_ID } from './default-user';
import type { AuthService } from './identity.service';
import { extractBearerToken } from './tokens';
// `request-identity.d.ts` augments `express.Request` with `userId` globally, by virtue of being
// part of the TypeScript program (`tsconfig.json`'s `include`) — a declaration file has no runtime
// form to import, so there is deliberately no import statement for it here.

/**
 * Paths the multi-tenant identity gate never touches, regardless of `SINGLE_USER_MODE`.
 *
 * - `/health` — the acceptance criteria name it explicitly; a load balancer or uptime check must
 *   not need a credential to ask "are you up".
 * - `/auth/*` — every route this ticket adds (`register`, `token`, `me`) plus every route the
 *   existing single-password `AuthManager` (`./auth.ts`) already owns (`login`, `logout`, `status`,
 *   `login.css`). A blanket gate in front of the very endpoints that hand out or check credentials
 *   would make it impossible to ever obtain one. `GET /auth/me` and `DELETE /auth/token` still
 *   require a valid bearer token — they just check it themselves (`identity.controller.ts`) instead
 *   of relying on this gate, which is what "except … auth routes" in the acceptance criteria means
 *   in practice: exempt from the *blanket* check, not exempt from authentication altogether.
 * - `/login` — `AuthManager`'s HTML sign-in page. It lives outside the `/auth/` prefix, so it needs
 *   its own line here.
 * - `/app` — the built web client's static shell (`main.ts`'s `mountWebClient`). Already documented
 *   there as carrying no diary content; gating it would 401 the HTML/JS/CSS a browser needs even to
 *   render a login screen, since a `<script src>` or a plain navigation cannot carry a bearer
 *   header. The client's actual data calls (`/entries`, `/insights`, …) are not exempt.
 */
const EXEMPT_PREFIXES = ['/health', '/auth/', '/login', '/app'];

function isExempt(path: string): boolean {
  return EXEMPT_PREFIXES.some((prefix) => path === prefix || path.startsWith(prefix));
}

/**
 * Installs the multi-tenant identity gate (M-1a, #45).
 *
 * Two modes, chosen by `singleUserMode`:
 *
 *  - **On** (the default — see `AppConfig.singleUserMode`'s doc comment in `config.ts`): every
 *    request is treated as the fixed `DEFAULT_USER_ID`, no token required. This is what makes the
 *    mobile dev loop and the web client keep working unchanged today — neither sends a bearer token
 *    yet, and none of this ticket's new endpoints are reachable from either client (out of scope).
 *  - **Off**: every non-exempt request must carry `Authorization: Bearer <token>` naming a live
 *    session, or the response is 401 before any controller runs.
 *
 * Registered on the raw Express instance, the same way `AuthManager.install` is (`./auth.ts`) and
 * for the same reason: it must run in front of every route Nest serves, including ones a 404
 * eventually, and a Nest guard scoped to particular controllers cannot see routes outside Nest
 * (there are none today, but the shape should not need to change if that ever stops being true).
 */
export function installIdentityGate(
  app: NestExpressApplication,
  authService: AuthService,
  singleUserMode: boolean,
): void {
  const server = app.getHttpAdapter().getInstance() as express.Express;

  server.use((req: Request, res: Response, next: NextFunction) => {
    if (isExempt(req.path)) {
      next();
      return;
    }

    if (singleUserMode) {
      req.userId = DEFAULT_USER_ID;
      next();
      return;
    }

    const token = extractBearerToken(req.get('authorization'));
    const userId = token ? authService.resolveToken(token) : null;
    if (!userId) {
      res.setHeader('Cache-Control', 'no-store');
      res.status(401).json({
        error: { code: 'unauthorized', message: 'A valid bearer token is required.' },
      });
      return;
    }

    req.userId = userId;
    next();
  });
}
