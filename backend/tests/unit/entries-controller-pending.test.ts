/**
 * P0-1 root cause: `POST /entries` and `POST /guided-entry-drafts/{key}/finalize` used to report
 * `analysis_pending: false` unconditionally, regardless of whether inference had actually run.
 *
 * That was invisible in the rest of the suite because every other test boots the app with
 * `NODE_ENV=test`, which wires `ENTRY_INFERENCE` to `ImmediateTestInference` (see
 * `app.module.ts`) — inference "completes" synchronously, so the hardcoded `false` happened to be
 * true by accident. In production `QueuedEntryInference.enqueueEntry` only queues a durable job
 * and returns null; the worker (a separate process) has not had a chance to run yet, so the entry
 * genuinely *is* still pending analysis at the moment this response is built. A client had no
 * honest signal telling it to poll.
 *
 * These tests exercise `EntriesController.create` and `GuidedDraftsController.finalize` directly
 * against a stub `EntriesService`, bypassing Nest's DI/`NODE_ENV` switch entirely, so both branches
 * of `createEntry`/`finalizeGuidedDraft` returning a null suggestion (the production shape) and a
 * non-null one (the test-double shape) are covered without needing two different app boots.
 */

import { describe, expect, it } from 'vitest';
import type { Request } from 'express';
import { EntriesController } from '../../src/entries/entries.controller';
import { GuidedDraftsController } from '../../src/entries/guided-drafts.controller';
import type { EntriesService } from '../../src/entries/entries.service';
import type { DiaryEntry, SuggestedFeeling } from '../../src/domain/types';

/** M-1b (#46): every controller handler now reads `req.userId`, set by `IdentityGate` in a real
 *  request. These tests call the controller directly, bypassing that middleware, so this stands
 *  in for it — the actual value is arbitrary, since nothing here asserts on which user was read. */
function fakeRequest(): Request {
  return { userId: 'user-1' } as unknown as Request;
}

function fakeEntry(overrides: Partial<DiaryEntry> = {}): DiaryEntry {
  return {
    id: 'entry-1',
    createdAt: '2026-08-29T09:00:00.000000',
    updatedAt: '2026-08-29T09:00:00.000000',
    entryDate: '2026-08-29',
    mode: 'freeform',
    rawText: 'Had a long, complicated day.',
    feelingKey: null,
    feelingKeys: [],
    feelingSource: 'unset',
    version: 1,
    feelingIntensity: null,
    feelingIntensities: {},
    ...overrides,
  } as DiaryEntry;
}

/** A stub carrying only what `create`/`finalize` touch on `EntriesService`. */
function stubService(options: {
  createResult?: { entry: DiaryEntry; suggestion: SuggestedFeeling | null };
  finalizeResult?: { entry: DiaryEntry; suggestion: SuggestedFeeling | null };
  analysis: {
    suggested: SuggestedFeeling | null;
    suggestedAll: SuggestedFeeling[];
    pending: boolean;
  };
}): {
  service: EntriesService;
  analysisForCalls: string[];
} {
  const analysisForCalls: string[] = [];
  const service = {
    createEntry: () => options.createResult,
    finalizeGuidedDraft: () => options.finalizeResult,
    analysisFor: (_userId: string, entryId: string) => {
      analysisForCalls.push(entryId);
      return options.analysis;
    },
  } as unknown as EntriesService;
  return { service, analysisForCalls };
}

/**
 * A stub carrying only what `create`/`finalize` touch on `EntriesRepository` — the pairings read
 * that E-1a added. No test in this file cares about pairings themselves (that is
 * `entries-topic-feelings.test.ts`'s job); this exists only so `toEntryOut` has something to call.
 */
function stubEntriesRepo(): { findTopicFeelingPairings: () => never[] } {
  return { findTopicFeelingPairings: () => [] };
}

/**
 * A stub carrying only what `create`/`finalize` touch on `TopicsService` — the `topics` read that
 * #81 added. No test in this file cares about topics themselves (that is
 * `entries-topics.test.ts`'s job); this exists only so `toEntryOut` has something to call.
 */
function stubTopicsService(): { topicsForEntry: () => never[] } {
  return { topicsForEntry: () => [] };
}

describe('POST /entries -- analysis_pending honesty', () => {
  it('reports the job as pending when createEntry could not suggest synchronously', () => {
    const entry = fakeEntry();
    const { service, analysisForCalls } = stubService({
      createResult: { entry, suggestion: null },
      analysis: { suggested: null, suggestedAll: [], pending: true },
    });
    const controller = new EntriesController(
      stubEntriesRepo() as never,
      service,
      undefined as never,
      undefined as never,
      stubTopicsService() as never,
    );

    const body = controller.create({ mode: 'freeform', raw_text: entry.rawText }, fakeRequest());

    expect(body.analysis_pending).toBe(true);
    expect(body.suggested_feeling).toBeNull();
    expect(body.suggested_feelings).toEqual([]);
    expect(analysisForCalls).toEqual([entry.id]);
  });

  it('reports the job as already settled once analysisFor finds a completed suggestion', () => {
    const entry = fakeEntry();
    const suggestion: SuggestedFeeling = { key: 'calm', confidence: 0.8 };
    const { service } = stubService({
      createResult: { entry, suggestion: null },
      analysis: { suggested: suggestion, suggestedAll: [suggestion], pending: false },
    });
    const controller = new EntriesController(
      stubEntriesRepo() as never,
      service,
      undefined as never,
      undefined as never,
      stubTopicsService() as never,
    );

    const body = controller.create({ mode: 'freeform', raw_text: entry.rawText }, fakeRequest());

    expect(body.analysis_pending).toBe(false);
    expect(body.suggested_feeling).toEqual(suggestion);
    expect(body.suggested_feelings).toEqual([suggestion]);
  });

  it('trusts a synchronous suggestion without consulting analysisFor (test-double path)', () => {
    const entry = fakeEntry();
    const suggestion: SuggestedFeeling = { key: 'neutral', confidence: 0 };
    const { service, analysisForCalls } = stubService({
      createResult: { entry, suggestion },
      analysis: { suggested: null, suggestedAll: [], pending: true }, // would be wrong if used
    });
    const controller = new EntriesController(
      stubEntriesRepo() as never,
      service,
      undefined as never,
      undefined as never,
      stubTopicsService() as never,
    );

    const body = controller.create({ mode: 'freeform', raw_text: entry.rawText }, fakeRequest());

    expect(body.analysis_pending).toBe(false);
    expect(body.suggested_feeling).toEqual(suggestion);
    expect(analysisForCalls).toEqual([]);
  });
});

describe('POST /guided-entry-drafts/{key}/finalize -- analysis_pending honesty', () => {
  it('reports the job as pending when finalizeGuidedDraft could not suggest synchronously', () => {
    const entry = fakeEntry({ mode: 'guided' });
    const { service, analysisForCalls } = stubService({
      finalizeResult: { entry, suggestion: null },
      analysis: { suggested: null, suggestedAll: [], pending: true },
    });
    const controller = new GuidedDraftsController(
      service,
      stubEntriesRepo() as never,
      undefined as never,
      stubTopicsService() as never,
    );

    const body = controller.finalize('draft-1', fakeRequest());

    expect(body.analysis_pending).toBe(true);
    expect(body.suggested_feelings).toEqual([]);
    expect(analysisForCalls).toEqual([entry.id]);
  });
});
