import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import type { Request, Response } from 'express';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AppModule } from './app.module';
import { AuthManager } from './auth/auth';
import { installIdentityGate } from './auth/identity.middleware';
import { AuthService } from './auth/identity.service';
import { ErrorEnvelopeFilter } from './common/http-exception.filter';
import { type AuthConfig, loadConfig } from './config';

/** Diary-bearing paths. Static assets under /app are excluded — they carry no diary content. */
const NO_STORE_PREFIXES = [
  '/entries',
  '/insights',
  '/experiments',
  '/monthly-summary',
  '/guiding-questions',
  '/transcriptions',
  '/guided-entry-drafts',
  '/export',
  '/import',
];

export interface CreateAppOptions {
  databasePath?: string;
  webDistPath?: string;
  auth?: AuthConfig;
  /** Overrides `AppConfig.singleUserMode` (`config.ts`) — the same injection shape `auth` already
   * uses, and for the same reason: tests need to flip this per-boot rather than through a process
   * env var shared by every test file in this suite's single worker thread. */
  singleUserMode?: boolean;
}

export async function createApp(
  databasePathOrOptions?: string | CreateAppOptions,
): Promise<NestExpressApplication> {
  const options: CreateAppOptions =
    typeof databasePathOrOptions === 'string'
      ? { databasePath: databasePathOrOptions }
      : (databasePathOrOptions ?? {});

  const app = await NestFactory.create<NestExpressApplication>(
    AppModule.forRoot(options.databasePath),
    { logger: ['error', 'warn'] },
  );

  app.useGlobalFilters(new ErrorEnvelopeFilter());

  // JSON parsing ignores audio/*. This bounded raw parser exposes recordings as a Buffer without
  // multipart copies or a persistent upload directory.
  app.useBodyParser('raw', { type: 'audio/*', limit: '25mb' });

  const runtimeConfig = loadConfig();

  // FR-025 (inherited from feature 003): keep diary content out of the browser's disk cache.
  app.use((req: Request, res: Response, next: () => void) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; connect-src 'self'; img-src 'self' data:; " +
        "style-src 'self'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    );
    if (NO_STORE_PREFIXES.some((prefix) => req.path.startsWith(prefix))) {
      res.setHeader('Cache-Control', 'no-store');
    }
    next();
  });

  new AuthManager(options.auth ?? runtimeConfig.auth).install(app);

  // M-1a (#45): the multi-tenant identity gate. Installed after `AuthManager` so the existing
  // single-password tunnel protection keeps running exactly as before — this only adds a second,
  // orthogonal check on top, never replaces the first one. `AuthService` is resolved from Nest's
  // own container rather than constructed here so both this gate and the `/auth/*` controller
  // share one `AuthService` instance, backed by the one `DIARY_DB` the rest of the app uses.
  installIdentityGate(
    app,
    app.get(AuthService),
    options.singleUserMode ?? runtimeConfig.singleUserMode,
  );

  mountWebClient(app, options.webDistPath ?? runtimeConfig.webDistPath);
  return app;
}

/**
 * Serves the built web client under `/app`.
 *
 * Three properties, each learned the hard way in feature 003:
 *  - the **prefix** exists because SPA routes would otherwise collide with `/entries` and `/insights`;
 *  - the **fallback** exists because `/app/calendar` is a client route, not a file — without it a
 *    reload returns a JSON 404 instead of the app;
 *  - the **guard** exists because an unconditional mount takes the API down on a fresh clone,
 *    which would break the Android app over a missing browser bundle.
 */
function mountWebClient(app: NestExpressApplication, webDistPath: string): void {
  const logger = new Logger('web');
  const exists = fs.existsSync(webDistPath) && fs.statSync(webDistPath).isDirectory();

  if (!exists) {
    logger.warn(
      `Web client not built at ${webDistPath} — serving the API only. ` +
        'Run `npm run build` in web/ to enable the browser client at /app.',
    );
    return;
  }

  app.useStaticAssets(webDistPath, { prefix: '/app' });
  // Registered after the static handler, so real files win and only unmatched paths fall through.
  app.use('/app', (_req: Request, res: Response) => {
    res.sendFile(path.join(webDistPath, 'index.html'));
  });
  logger.log(`Serving the web client from ${webDistPath} at /app`);
}

async function bootstrap(): Promise<void> {
  const config = loadConfig();
  const logger = new Logger('bootstrap');
  const app = await createApp({
    databasePath: config.databasePath,
    webDistPath: config.webDistPath,
    auth: config.auth,
    singleUserMode: config.singleUserMode,
  });

  await app.listen(config.port, config.host);
  logger.log(`Diary API listening on ${config.host}:${config.port}`);
  logger.log(`Reading the diary at ${config.databasePath} (never migrated, never altered)`);
  logger.log(
    config.singleUserMode
      ? 'SINGLE_USER_MODE is on: every request resolves to the default user, no bearer token required.'
      : 'SINGLE_USER_MODE is off: every route but /health and /auth/* requires a valid bearer token.',
  );
  if (config.auth.enabled) {
    logger.log(
      `Authentication protects ${config.auth.publicHostname ?? 'all hostnames'}; session cookies are ${config.auth.secureCookie ? 'Secure' : 'not Secure'}.`,
    );
  } else if (!['127.0.0.1', '::1', 'localhost'].includes(config.host)) {
    logger.warn(
      'Remote access is enabled and there is no login. Keep this port behind a trusted LAN or VPN; never port-forward it.',
    );
  }
}

if (require.main === module) {
  void bootstrap();
}
