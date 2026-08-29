/**
 * Request-context augmentation for M-1a (#45).
 *
 * `IdentityGate` (`./identity.middleware.ts`) is the only writer of `req.userId`. Nothing reads it
 * yet — no route scopes a query by it — because that is M-1b's job, deliberately kept out of this
 * ticket (task 4: "identity + plumbing only"). This file exists so the field has one, real,
 * type-checked declaration instead of every future reader reaching for `(req as any).userId`.
 */
export {};

declare global {
  namespace Express {
    interface Request {
      /** The authenticated user, once `IdentityGate` has run. Always set on a request that
       * reaches a non-exempt route — `IdentityGate` either sets it or ends the response with 401
       * itself, so a handler downstream of it never needs to re-check for `undefined`. */
      userId?: string;
    }
  }
}
