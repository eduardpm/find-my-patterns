import { describe, expect, it, vi } from 'vitest';
import { createScopedDb, UnscopedQueryError } from '../../src/db/scoped-db';
import type { DiaryDatabase } from '../../src/db/database';

function fakeRaw(): DiaryDatabase {
  return {
    prepare: vi.fn().mockReturnValue({ get: vi.fn(), all: vi.fn(), run: vi.fn() }),
    transaction: vi.fn((fn: () => unknown) => fn()),
    close: vi.fn(),
    readonlyPragma: vi.fn().mockReturnValue([]),
  } as unknown as DiaryDatabase;
}

describe('ScopedDb (M-1b, #46)', () => {
  it('forUser refuses an empty userId — the one thing standing between a request that lost its identity and a query against nobody', () => {
    const scoped = createScopedDb(fakeRaw());
    expect(() => scoped.forUser('')).toThrow(/non-empty userId/);
  });

  it('lets a query naming a per-user table through once it mentions user_id', () => {
    const raw = fakeRaw();
    const scoped = createScopedDb(raw);
    const handle = scoped.forUser('user-a');
    expect(() =>
      handle.prepare('SELECT * FROM diary_entries WHERE user_id = ? AND entry_date = ?'),
    ).not.toThrow();
    expect(raw.prepare).toHaveBeenCalledWith(
      'SELECT * FROM diary_entries WHERE user_id = ? AND entry_date = ?',
    );
  });

  it('refuses a SELECT against a per-user table that never mentions user_id — the leak-by-omission shape', () => {
    const scoped = createScopedDb(fakeRaw());
    const handle = scoped.forUser('user-a');
    expect(() => handle.prepare('SELECT * FROM diary_entries WHERE entry_date = ?')).toThrow(
      UnscopedQueryError,
    );
  });

  it('refuses an INSERT whose column list forgot user_id — the exact footgun #134 documented: a forgotten column silently defaults to DEFAULT_USER_ID', () => {
    const scoped = createScopedDb(fakeRaw());
    const handle = scoped.forUser('user-a');
    expect(() =>
      handle.prepare('INSERT INTO topics (id, name, aliases) VALUES (?, ?, ?)'),
    ).toThrow(UnscopedQueryError);
  });

  it('lets an INSERT that includes user_id in its column list through', () => {
    const scoped = createScopedDb(fakeRaw());
    const handle = scoped.forUser('user-a');
    expect(() =>
      handle.prepare('INSERT INTO topics (id, user_id, name, aliases) VALUES (?, ?, ?, ?)'),
    ).not.toThrow();
  });

  it('never touches shared reference vocabulary — feelings/feeling_groups/guiding_questions carry no user_id column at all', () => {
    const scoped = createScopedDb(fakeRaw());
    const handle = scoped.forUser('user-a');
    expect(() => handle.prepare('SELECT "key", label FROM feelings ORDER BY sort_order')).not.toThrow();
    expect(() => handle.prepare('SELECT "key" FROM guiding_questions')).not.toThrow();
  });

  it('passes transaction, close and readonlyPragma straight through to the raw connection', () => {
    const raw = fakeRaw();
    const scoped = createScopedDb(raw);
    const handle = scoped.forUser('user-a');
    handle.transaction(() => 42);
    expect(raw.transaction).toHaveBeenCalled();
    handle.close();
    expect(raw.close).toHaveBeenCalled();
    handle.readonlyPragma('SELECT 1');
    expect(raw.readonlyPragma).toHaveBeenCalledWith('SELECT 1');
  });
});
