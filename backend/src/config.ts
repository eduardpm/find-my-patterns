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
  };
}
