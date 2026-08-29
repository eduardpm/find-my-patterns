/**
 * #88 fix 4 — a singleton guard on the worker.
 *
 * The incident's root-cause analysis (§2f) found three worker processes left running from
 * repeated restarts during a seeding session, all racing to narrate the same patterns: nothing
 * stopped two workers from both calling the model for one pattern before either write landed.
 * `acquireWorkerLock` is a PID lock file beside the diary that makes a second worker exit instead
 * of competing.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encodeDate, encodeDateTime, nowUtc, todayLocal } from '../src/db/codecs';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { initDiary } from '../src/db/init';
import { acquireWorkerLock, runWorker, type WorkerLock } from '../src/inference/worker';

let dir: string;
let dbPath: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-worker-lock-'));
  dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  process.env.DATABASE_PATH = dbPath;
});

afterEach(() => {
  delete process.env.DATABASE_PATH;
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('acquireWorkerLock', () => {
  it('grants the lock when nothing else holds it, and the lock file names the holder', () => {
    const lock = acquireWorkerLock(dbPath);
    expect(lock).not.toBeNull();
    expect(fs.existsSync(`${dbPath}.worker.lock`)).toBe(true);
    expect(fs.readFileSync(`${dbPath}.worker.lock`, 'utf8').trim()).toBe(String(process.pid));
    lock?.release();
  });

  it('refuses a second acquisition while a live process holds it', () => {
    const first = acquireWorkerLock(dbPath);
    expect(first).not.toBeNull();

    // Same test process, so `process.pid` is genuinely alive — this is exactly the check a real
    // second worker process would fail against a real first one.
    const second = acquireWorkerLock(dbPath);
    expect(second).toBeNull();

    first?.release();
  });

  it('releasing frees the lock for the next acquisition', () => {
    const first = acquireWorkerLock(dbPath);
    first?.release();
    expect(fs.existsSync(`${dbPath}.worker.lock`)).toBe(false);

    const second = acquireWorkerLock(dbPath);
    expect(second).not.toBeNull();
    second?.release();
  });

  it('takes over a stale lock left by a PID that is no longer running', () => {
    // PID 1 always exists on a real machine, but never as this test's own process — swap in an
    // unreachable, syntactically valid PID instead so the "not alive" branch is exercised without
    // depending on which PIDs happen to be free on the host.
    const deadPid = 999_999;
    fs.writeFileSync(`${dbPath}.worker.lock`, String(deadPid));

    const lock = acquireWorkerLock(dbPath);
    expect(lock).not.toBeNull();
    expect(fs.readFileSync(`${dbPath}.worker.lock`, 'utf8').trim()).toBe(String(process.pid));
    lock?.release();
  });
});

describe('runWorker (#88 fix 4)', () => {
  let lock: WorkerLock | null;
  let stderrSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
  });

  afterEach(() => {
    lock?.release();
    lock = null;
    stderrSpy.mockRestore();
  });

  it('exits without processing anything when another worker already holds the lock', async () => {
    const now = encodeDateTime(nowUtc());
    openDiaryWithQueuedJob(dbPath, now);

    // Simulate a live competing worker by holding the lock ourselves first.
    lock = acquireWorkerLock(dbPath);
    expect(lock).not.toBeNull();

    await runWorker(true);

    // The queued job is exactly as it was — the second worker never touched the diary.
    const db = openDiary(dbPath);
    const job = db.prepare('SELECT status FROM inference_jobs').get() as { status: string };
    db.close();
    expect(job.status).toBe('queued');

    expect(
      stderrSpy.mock.calls.some((call) =>
        String(call[0]).includes('another worker already holds the lock'),
      ),
    ).toBe(true);
  });

  it('proceeds normally once the lock is free', async () => {
    const now = encodeDateTime(nowUtc());
    openDiaryWithQueuedJob(dbPath, now);

    // Stubbed rather than left to hit a real Ollama: the point of this test is the lock, not
    // analysis, and a real network call has no place in this suite either way.
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
      const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
      const isAnalysisCall = Array.isArray(body.messages) && body.messages.length > 0;
      return {
        ok: true,
        status: 200,
        json: async () =>
          isAnalysisCall
            ? {
                message: {
                  content: JSON.stringify({
                    feelings: [
                      { group_key: 'uplifted', feeling_key: 'energised', confidence: 0.8 },
                    ],
                    topics: [],
                    topic_feelings: [],
                  }),
                },
              }
            : { message: {} },
      } as Response;
    });

    await runWorker(true);
    fetchSpy.mockRestore();

    const db = openDiary(dbPath);
    const job = db.prepare('SELECT status FROM inference_jobs').get() as { status: string };
    db.close();
    expect(job.status).toBe('completed');
    expect(fs.existsSync(`${dbPath}.worker.lock`)).toBe(false);
  });
});

function openDiaryWithQueuedJob(target: string, now: string): void {
  const db: DiaryDatabase = openDiary(target);
  db.prepare(
    `INSERT INTO diary_entries
     (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
     VALUES ('entry-1', ?, ?, ?, 'freeform', 'A local test entry', NULL, 'unset', 1)`,
  ).run(now, now, encodeDate(todayLocal()));
  db.prepare(
    `INSERT INTO inference_jobs
     (id, kind, entry_id, status, result_json, error_text, attempts, created_at, started_at, completed_at)
     VALUES ('job-1', 'entry_analysis', 'entry-1', 'queued', NULL, NULL, 0, ?, NULL, NULL)`,
  ).run(now);
  db.close();
}
