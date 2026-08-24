import type { NestExpressApplication } from '@nestjs/platform-express';
import express, { type NextFunction, type Request, type Response } from 'express';
import { randomBytes } from 'node:crypto';
import type { AuthConfig } from '../config';
import { verifyPassword } from './password';

const COOKIE_NAME = 'diary_session';
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILURES = 8;

interface Session {
  expiresAt: number;
}

export class AuthManager {
  private readonly sessions = new Map<string, Session>();
  private failedAt: number[] = [];

  constructor(private readonly config: AuthConfig) {}

  install(app: NestExpressApplication): void {
    const server = app.getHttpAdapter().getInstance() as express.Express;
    server.get('/auth/status', (req: Request, res: Response) => {
      res.json({ enabled: this.config.enabled && this.protects(req) });
    });
    if (!this.config.enabled) return;

    server.use('/auth/login', express.urlencoded({ extended: false, limit: '4kb' }));
    server.get('/auth/login.css', (_req: Request, res: Response) => this.sendLoginCss(res));
    server.get('/login', (req: Request, res: Response) => this.sendLoginPage(req, res));
    server.post('/auth/login', (req: Request, res: Response, next: NextFunction) => {
      void this.login(req, res).catch(next);
    });
    server.post('/auth/logout', (req: Request, res: Response) => this.logout(req, res));
    server.use((req: Request, res: Response, next: NextFunction) =>
      this.requireSession(req, res, next),
    );
  }

  private protects(req: Request): boolean {
    if (!this.config.publicHostname) return true;
    return req.hostname.toLowerCase() === this.config.publicHostname;
  }

  private isPublicPath(path: string): boolean {
    return path === '/health' || path === '/login' || path.startsWith('/auth/');
  }

  private requireSession(req: Request, res: Response, next: NextFunction): void {
    if (!this.protects(req) || this.isPublicPath(req.path)) return next();
    const token = readCookie(req, COOKIE_NAME);
    if (token && this.consumeValidSession(token)) {
      const origin = req.get('origin');
      if (origin && isUnsafeMethod(req.method) && !isSameOrigin(origin, req.get('host'))) {
        res.status(403).json({
          error: { code: 'forbidden_origin', message: 'The request origin is not allowed.' },
        });
        return;
      }
      return next();
    }

    res.setHeader('Cache-Control', 'no-store');
    if (req.path === '/' || req.path.startsWith('/app')) {
      const nextPath = safeNext(req.originalUrl);
      res.redirect(303, `/login?next=${encodeURIComponent(nextPath)}`);
      return;
    }
    res
      .status(401)
      .json({ error: { code: 'unauthorized', message: 'Sign in to access the diary.' } });
  }

  private async login(req: Request, res: Response): Promise<void> {
    res.setHeader('Cache-Control', 'no-store');
    if (!this.protects(req)) {
      res.redirect(303, safeNext(asString(req.body?.next)));
      return;
    }
    this.pruneFailures();
    if (this.failedAt.length >= MAX_FAILURES) {
      res.setHeader('Retry-After', String(Math.ceil(LOGIN_WINDOW_MS / 1000)));
      this.sendLoginPage(req, res, 'Too many attempts. Try again in 15 minutes.', 429);
      return;
    }

    const email = asString(req.body?.email).trim().toLowerCase();
    const password = asString(req.body?.password);
    // Always perform the expensive hash verification, even when the email is wrong.
    const passwordOk = await verifyPassword(password, this.config.passwordHash!);
    if (email !== this.config.email || !passwordOk) {
      this.failedAt.push(Date.now());
      this.sendLoginPage(req, res, 'Email or password is incorrect.', 401);
      return;
    }

    this.failedAt = [];
    const token = randomBytes(32).toString('base64url');
    const maxAgeMs = this.config.sessionHours * 60 * 60 * 1000;
    this.sessions.set(token, { expiresAt: Date.now() + maxAgeMs });
    res.cookie(COOKIE_NAME, token, this.cookieOptions(maxAgeMs));
    res.redirect(303, safeNext(asString(req.body?.next)));
  }

  private logout(req: Request, res: Response): void {
    const token = readCookie(req, COOKIE_NAME);
    if (token) this.sessions.delete(token);
    res.setHeader('Cache-Control', 'no-store');
    res.clearCookie(COOKIE_NAME, this.cookieOptions(0));
    res.redirect(303, '/login?signedOut=1');
  }

  private consumeValidSession(token: string): boolean {
    const session = this.sessions.get(token);
    if (!session) return false;
    if (session.expiresAt <= Date.now()) {
      this.sessions.delete(token);
      return false;
    }
    return true;
  }

  private pruneFailures(): void {
    const cutoff = Date.now() - LOGIN_WINDOW_MS;
    this.failedAt = this.failedAt.filter((attempt) => attempt > cutoff);
    for (const [token, session] of this.sessions) {
      if (session.expiresAt <= Date.now()) this.sessions.delete(token);
    }
  }

  private cookieOptions(maxAge: number) {
    return {
      httpOnly: true,
      secure: this.config.secureCookie,
      sameSite: 'strict' as const,
      path: '/',
      maxAge,
    };
  }

  private sendLoginPage(req: Request, res: Response, error = '', status = 200): void {
    res.status(status);
    res.type('html');
    res.setHeader('Cache-Control', 'no-store');
    const next = safeNext(asString(req.query.next) || asString(req.body?.next));
    const signedOut = req.query.signedOut === '1';
    res.send(loginHtml(next, error, signedOut));
  }

  private sendLoginCss(res: Response): void {
    res.type('css').send(LOGIN_CSS);
  }
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function safeNext(value: string): string {
  return value === '/app' || value.startsWith('/app/') ? value : '/app/today';
}

function readCookie(req: Request, name: string): string | undefined {
  for (const part of (req.headers.cookie ?? '').split(';')) {
    const [key, ...value] = part.trim().split('=');
    if (key === name) return decodeURIComponent(value.join('='));
  }
  return undefined;
}

function isUnsafeMethod(method: string): boolean {
  return !['GET', 'HEAD', 'OPTIONS'].includes(method.toUpperCase());
}

function isSameOrigin(origin: string, host: string | undefined): boolean {
  if (!host) return false;
  try {
    return new URL(origin).host.toLowerCase() === host.toLowerCase();
  } catch {
    return false;
  }
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>'"]/g,
    (char) =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        "'": '&#39;',
        '"': '&quot;',
      })[char]!,
  );
}

function loginHtml(next: string, error: string, signedOut: boolean): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sign in · Mood diary</title><link rel="stylesheet" href="/auth/login.css"></head>
<body><main><section class="login-card"><div class="mark" aria-hidden="true">✦</div>
<p class="eyebrow">Private space</p><h1>Welcome back</h1><p class="intro">Sign in to open your mood diary.</p>
${signedOut ? '<p class="notice">You have been signed out.</p>' : ''}
${error ? `<p class="error" role="alert">${escapeHtml(error)}</p>` : ''}
<form method="post" action="/auth/login"><input type="hidden" name="next" value="${escapeHtml(next)}">
<label>Email<input name="email" type="email" autocomplete="username" inputmode="email" required autofocus></label>
<label>Password<input name="password" type="password" autocomplete="current-password" required></label>
<button type="submit">Sign in</button></form>
<p class="privacy">Your credentials are checked only by your self-hosted diary.</p>
</section></main></body></html>`;
}

const LOGIN_CSS = `:root{color-scheme:light dark;font-family:Inter,ui-sans-serif,system-ui,sans-serif}*{box-sizing:border-box}body{margin:0;min-height:100vh;color:#28232f;background:radial-gradient(circle at 20% 0,#eee5fa 0,transparent 38rem),#f8f6fa}main{min-height:100vh;display:grid;place-items:center;padding:1.5rem}.login-card{width:min(100%,25rem);padding:2rem;border:1px solid #ded6e5;border-radius:1.4rem;background:rgba(255,255,255,.88);box-shadow:0 1.2rem 4rem rgba(49,35,65,.12);backdrop-filter:blur(16px)}.mark{font-size:2rem;color:#6e4d8c}.eyebrow{margin:.4rem 0;color:#6e4d8c;font-weight:700;letter-spacing:.08em;text-transform:uppercase;font-size:.72rem}h1{margin:.2rem 0;font-size:2rem}.intro,.privacy{color:#68606f}.notice,.error{padding:.75rem 1rem;border-radius:.75rem}.notice{background:#e5f5eb;color:#245b38}.error{background:#fde8e8;color:#872828}form{display:grid;gap:1rem;margin-top:1.5rem}label{display:grid;gap:.4rem;font-weight:650}input{width:100%;padding:.8rem .9rem;border:1px solid #bdb2c6;border-radius:.7rem;background:#fff;color:#28232f;font:inherit}input:focus-visible,button:focus-visible{outline:3px solid #9d79bd;outline-offset:2px}button{margin-top:.3rem;padding:.85rem 1rem;border:0;border-radius:999px;background:#6e4d8c;color:#fff;font:inherit;font-weight:700;cursor:pointer}.privacy{margin:1.25rem 0 0;font-size:.8rem;line-height:1.45}@media(prefers-color-scheme:dark){body{color:#f5eff8;background:#17131b}.login-card{background:#211b27;border-color:#43394b}.intro,.privacy{color:#c8becf}input{background:#17131b;color:#fff;border-color:#675b70}}`;
