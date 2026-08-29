export interface LoginRateLimiterOptions {
  maxAttempts: number;
  windowMs: number;
  /** Injectable so the reset/expiry path is deterministic in tests (task 5) — a real 15-minute
   * wait, or fake timers threaded through Nest's DI, would make that path far more expensive to
   * cover than the behaviour deserves. */
  now?: () => number;
}

/**
 * A simple in-memory login throttle (task 5: "a simple in-memory counter is acceptable now").
 *
 * Keyed per normalized email rather than globally, unlike the existing single-user
 * `AuthManager`'s counter (`./auth.ts`) — that one has exactly one account to protect, but the
 * moment there is more than one, a global counter lets an attacker lock every account out by
 * repeatedly failing against just one of them. Per-email bounds the blast radius to the account
 * actually under attack.
 *
 * In-memory and per-process, same as `AuthManager`'s: a restart clears every counter. That is an
 * acceptable trade for "part 1" plumbing — the failure mode of over-throttling (a legitimate user
 * briefly locked out) is far cheaper than the failure mode of a durable store (a new table and
 * cleanup job for a counter that self-heals every 15 minutes anyway).
 */
export class LoginRateLimiter {
  private readonly failuresByEmail = new Map<string, number[]>();
  private readonly maxAttempts: number;
  private readonly windowMs: number;
  private readonly now: () => number;

  constructor(options: LoginRateLimiterOptions) {
    this.maxAttempts = options.maxAttempts;
    this.windowMs = options.windowMs;
    this.now = options.now ?? Date.now;
  }

  isBlocked(email: string): boolean {
    return this.recentFailures(email).length >= this.maxAttempts;
  }

  recordFailure(email: string): void {
    const failures = this.recentFailures(email);
    failures.push(this.now());
    this.failuresByEmail.set(email, failures);
  }

  reset(email: string): void {
    this.failuresByEmail.delete(email);
  }

  private recentFailures(email: string): number[] {
    const cutoff = this.now() - this.windowMs;
    const failures = (this.failuresByEmail.get(email) ?? []).filter(
      (attemptAt) => attemptAt > cutoff,
    );
    this.failuresByEmail.set(email, failures);
    return failures;
  }
}
