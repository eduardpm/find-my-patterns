import * as path from 'node:path';

/**
 * Runtime configuration. Defaults match what the clients already expect, so no client needs
 * reconfiguring (FR-006, SC-008).
 */

const REPO_ROOT = path.resolve(__dirname, '..', '..');

export interface AppConfig {
  /** Path to the existing diary file. Never created, never migrated — only opened. */
  databasePath: string;
  port: number;
  host: string;
  /** Local Ollama endpoint used only by the separate inference worker. */
  ollamaUrl: string;
  ollamaModel: string;
  /** Formatting runs behind a polled audio job, so a cold local model gets a longer budget. */
  transcriptFormattingWaitMs: number;
  /** Local whisper.cpp executable and model used for browser audio transcription. */
  whisperCommand: string;
  whisperModelPath: string;
  whisperLanguage: string;
  transcriptionTimeoutMs: number;
  /** Built web client. Missing is fine — the API still serves (FR-016). */
  webDistPath: string;
  auth: AuthConfig;
  /**
   * M-1a, #45: whether every route (other than health + auth) is gated behind the new per-user
   * bearer token, with the resolved identity attached to the request as `req.userId`.
   *
   * Defaults to `true` — the multi-tenant identity plumbing exists starting with this ticket, but
   * neither client can register or log in yet (that is explicitly out of scope here), so flipping
   * the default to `false` today would 401 every request the mobile app and the web client make.
   * `loadConfig()`'s own doc comment is the rule this follows: "Defaults match what the clients
   * already expect, so no client needs reconfiguring." A later ticket flips this default once a
   * client can actually complete the register/login round trip; until then, set
   * `SINGLE_USER_MODE=false` to exercise the real multi-tenant gate (used by this backend's own
   * e2e suite, see `tests/contract/identity.test.ts`).
   */
  singleUserMode: boolean;
  billing: BillingConfig;
}

/**
 * M-2, #47: server-side entitlements. `googlePlay` is `undefined` whenever `manualEntitlements` is
 * `true` — nothing constructs `GooglePlayVerifier` in that mode (`app.module.ts`), so there is
 * nothing to validate the service-account fields for. When `manualEntitlements` is `false`,
 * `googlePlay` is validated only lazily, the first time `POST /billing/play/verify` actually needs
 * it — see the doc comment below on why config *loading* never fails over this.
 */
export interface BillingConfig {
  /** Dev mode: `POST /billing/play/verify` always succeeds without contacting Google
   * (`ManualPlayVerifier`, `billing/play-verifier.ts`), and `POST /billing/admin/grant` — otherwise
   * a 404 — becomes reachable. Defaults to `false`: a deployment that never opts in must not gain a
   * route that grants premium to anyone who can reach it. */
  manualEntitlements: boolean;
  googlePlay?: GooglePlayConfig;
  /** How often the background sweep drops expired premium entitlements to free
   * (`billing/entitlements.service.ts#sweepExpired`). Daily by default, matching the issue's
   * "poll-on-verify plus a daily sweep is acceptable." */
  entitlementsSweepIntervalMs: number;
}

export interface GooglePlayConfig {
  serviceAccountEmail: string;
  /** PEM. `.env` files and shells cannot carry a literal newline in a value without escaping, so
   * this is unescaped here — once — rather than in `play-verifier.ts`, keeping "the environment's
   * on-disk representation of a PEM" a `config.ts` concern the same way every other env parsing is. */
  privateKey: string;
  packageName: string;
}

export interface AuthConfig {
  enabled: boolean;
  email?: string;
  passwordHash?: string;
  /** Exact tunnel hostname to protect. Undefined protects every hostname. */
  publicHostname?: string;
  secureCookie: boolean;
  sessionHours: number;
}

function parseBoolean(name: string, fallback: boolean): boolean {
  const value = process.env[name];
  if (value === undefined) return fallback;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new Error(`${name} must be either "true" or "false".`);
}

export function loadAuthConfig(): AuthConfig {
  const enabled = parseBoolean('AUTH_ENABLED', false);
  const email = process.env.AUTH_EMAIL?.trim().toLowerCase() || undefined;
  const passwordHash = process.env.AUTH_PASSWORD_HASH || undefined;
  const publicHostname = process.env.AUTH_PUBLIC_HOSTNAME?.trim().toLowerCase() || undefined;
  const sessionHours = Number(process.env.AUTH_SESSION_HOURS ?? 12);

  if (!Number.isFinite(sessionHours) || sessionHours <= 0 || sessionHours > 168) {
    throw new Error('AUTH_SESSION_HOURS must be greater than 0 and no more than 168.');
  }
  if (enabled && (!email || !passwordHash)) {
    throw new Error(
      'Authentication is enabled but AUTH_EMAIL or AUTH_PASSWORD_HASH is missing. Refusing to start unprotected.',
    );
  }

  return {
    enabled,
    email,
    passwordHash,
    publicHostname,
    secureCookie: parseBoolean('AUTH_SECURE_COOKIE', enabled),
    sessionHours,
  };
}

/**
 * M-2, #47. Deliberately never throws over a missing `GOOGLE_PLAY_*` value — see `BillingConfig`'s
 * doc comment for why that check is deferred to the first real call to `GooglePlayVerifier` instead
 * of failing every server boot on a deployment that has not wired up Play billing yet, which is
 * every deployment of this project so far.
 */
export function loadBillingConfig(): BillingConfig {
  const manualEntitlements = parseBoolean('MANUAL_ENTITLEMENTS', false);

  const serviceAccountEmail = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL;
  // `\n` survives most ways of putting a PEM into a single-line env var (a `.env` file, a shell
  // export, a secrets manager's flat key/value store); a real embedded newline would too, so this
  // only ever replaces the two-character escape sequence, never a byte that was already a newline.
  const privateKey = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_KEY?.replace(/\\n/g, '\n');
  const packageName = process.env.GOOGLE_PLAY_PACKAGE_NAME;
  const googlePlay =
    serviceAccountEmail && privateKey && packageName
      ? { serviceAccountEmail, privateKey, packageName }
      : undefined;

  const entitlementsSweepIntervalMs = Number(
    process.env.ENTITLEMENTS_SWEEP_INTERVAL_MS ?? 24 * 60 * 60 * 1000,
  );
  if (!Number.isFinite(entitlementsSweepIntervalMs) || entitlementsSweepIntervalMs < 60_000) {
    throw new Error(
      'ENTITLEMENTS_SWEEP_INTERVAL_MS must be a number of at least 60000 (1 minute).',
    );
  }

  return { manualEntitlements, googlePlay, entitlementsSweepIntervalMs };
}

/**
 * `DATABASE_PATH` is the plain form. `DATABASE_URL` (`sqlite:///…`) is still accepted so an
 * existing environment set up for the previous implementation keeps working unchanged.
 */
function resolveDatabasePath(): string {
  const explicit = process.env.DATABASE_PATH;
  if (explicit) return path.resolve(explicit);

  const url = process.env.DATABASE_URL;
  if (url?.startsWith('sqlite:')) {
    const withoutScheme = url.replace(/^sqlite:\/{2,}/, '');
    return path.resolve(withoutScheme.startsWith('/') ? withoutScheme : withoutScheme);
  }

  return path.resolve(REPO_ROOT, 'data', 'diary.db');
}

export function loadConfig(): AppConfig {
  const transcriptFormattingWaitMs = Number(process.env.TRANSCRIPT_FORMATTING_WAIT_MS ?? 90_000);
  if (
    !Number.isFinite(transcriptFormattingWaitMs) ||
    transcriptFormattingWaitMs < 1_000 ||
    transcriptFormattingWaitMs > 180_000
  ) {
    throw new Error('TRANSCRIPT_FORMATTING_WAIT_MS must be between 1000 and 180000.');
  }

  const transcriptionTimeoutMs = Number(process.env.TRANSCRIPTION_TIMEOUT_MS ?? 120_000);
  if (
    !Number.isFinite(transcriptionTimeoutMs) ||
    transcriptionTimeoutMs < 1_000 ||
    transcriptionTimeoutMs > 600_000
  ) {
    throw new Error('TRANSCRIPTION_TIMEOUT_MS must be between 1000 and 600000.');
  }

  return {
    databasePath: resolveDatabasePath(),
    port: Number(process.env.PORT ?? 8000),
    // Loopback is the safe default for an unauthenticated diary. Phone access is an explicit
    // deployment choice (`HOST=0.0.0.0`) that the startup log and README call out clearly.
    host: process.env.HOST ?? '127.0.0.1',
    ollamaUrl: (process.env.OLLAMA_URL ?? 'http://127.0.0.1:11434').replace(/\/$/, ''),
    ollamaModel: process.env.OLLAMA_MODEL ?? 'qwen3:4b',
    transcriptFormattingWaitMs,
    whisperCommand:
      process.env.WHISPER_COMMAND ??
      path.resolve(REPO_ROOT, 'tools', 'whisper', 'bin', 'whisper-cli'),
    whisperModelPath:
      process.env.WHISPER_MODEL_PATH ?? path.resolve(REPO_ROOT, 'models', 'ggml-base.bin'),
    whisperLanguage: process.env.WHISPER_LANGUAGE ?? 'auto',
    transcriptionTimeoutMs,
    webDistPath: process.env.WEB_DIST_PATH ?? path.resolve(REPO_ROOT, 'web', 'dist'),
    auth: loadAuthConfig(),
    singleUserMode: parseBoolean('SINGLE_USER_MODE', true),
    billing: loadBillingConfig(),
  };
}
