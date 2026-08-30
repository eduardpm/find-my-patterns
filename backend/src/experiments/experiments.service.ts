import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  decodeDate,
  decodeDateTime,
  encodeDate,
  encodeDateTime,
  nowUtc,
  serializeDate,
  serializeDateTime,
  todayLocal,
  type PlainDate,
} from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import { CONFIRMED_FEELING_SOURCES } from '../insights/constants';
import { PatternsService } from '../insights/patterns.service';
import {
  addDays,
  baselineWindowFor,
  elapsedWindow,
  experimentVerdict,
  windowAssociation,
  windowLengthDays,
  type WindowAssociation,
  type WindowCounts,
} from './experiment-math';
import {
  experimentConstants,
  MAX_EXPERIMENT_LENGTH_DAYS,
  MIN_EXPERIMENT_LENGTH_DAYS,
  type ExperimentConstants,
} from './constants';

export type HypothesisKind = 'more_of' | 'less_of';
export type ExperimentStatus = 'active' | 'finished' | 'abandoned';

export interface ExperimentOut {
  id: string;
  pattern_topic: string;
  pattern_feeling: string;
  hypothesis_kind: HypothesisKind;
  start_date: string;
  end_date: string;
  status: ExperimentStatus;
  created_at: string;
  constants: ExperimentConstants;
}

export interface WindowOut {
  start_date: string;
  end_date: string;
  total_days: number;
  days_with_topic: number;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
}

export interface ExperimentResultsOut {
  experiment: ExperimentOut;
  experiment_window: WindowOut;
  baseline_window: WindowOut;
  verdict_text: string;
  insufficient_data: boolean;
  constants: ExperimentConstants;
}

export interface CreateExperimentInput {
  patternTopic: string;
  patternFeeling: string;
  hypothesisKind: HypothesisKind;
  startDate?: PlainDate;
  lengthDays?: number;
}

export class ExperimentNotFoundError extends Error {}
export class NoActiveExperimentError extends Error {}
export class ActiveExperimentExistsError extends Error {}
export class NonQualifyingPatternError extends Error {}
export class ExperimentNotActiveError extends Error {}
export class InvalidExperimentLengthError extends Error {}

interface ExperimentRow {
  id: string;
  pattern_topic: string;
  pattern_feeling: string;
  hypothesis_kind: string;
  start_date: string;
  end_date: string;
  status: string;
  created_at: string;
}

/**
 * N-of-1 experiments — the honest bridge from correlation toward causation (R-3a).
 *
 * Three rules, each guarding a way this could quietly turn into a claim the diary cannot back:
 *
 *  - **Observation only.** Nothing here writes to `patterns`, `pattern_entries` or any entry.
 *    Starting or abandoning an experiment changes what this module's own tables say and nothing
 *    else — `PatternsService` is used strictly for reading (recompute, then check the current
 *    list), never for writing.
 *  - **One at a time.** A second active experiment would make "the experiment window" ambiguous —
 *    which one owns a given day — so creation is refused while one is already running.
 *  - **Only a qualifying pattern can be tested.** "Qualifying" is not redefined here: it is
 *    whatever `PatternsService` currently lists as an active forward pattern for that
 *    topic/feeling pair, which already encodes the minimum occurrence count and the minimum lift
 *    (`insights/constants.ts`). Reusing that list rather than re-checking the thresholds means an
 *    experiment can only ever be started on exactly the patterns the Insights view itself is
 *    willing to show as real.
 */
@Injectable()
export class ExperimentsService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly patterns: PatternsService,
  ) {}

  // -------------------------------------------------------------------------------------------
  // Status
  // -------------------------------------------------------------------------------------------

  /**
   * An experiment's `end_date` is a plan, not a poll — nothing flips it to `finished` on its own.
   * This is the one place that happens, run at the top of every public method so a client never
   * sees a stale `active` row for a window that has already closed, however it got here.
   */
  private syncFinished(userId: string, today: PlainDate): void {
    this.db
      .forUser(userId)
      .prepare(
        `UPDATE experiments SET status = 'finished'
         WHERE user_id = ? AND status = 'active' AND end_date < ?`,
      )
      .run(userId, encodeDate(today));
  }

  private toOut(row: ExperimentRow): ExperimentOut {
    return {
      id: row.id,
      pattern_topic: row.pattern_topic,
      pattern_feeling: row.pattern_feeling,
      hypothesis_kind: row.hypothesis_kind as HypothesisKind,
      start_date: row.start_date,
      end_date: row.end_date,
      status: row.status as ExperimentStatus,
      created_at: serializeDateTime(decodeDateTime(row.created_at)),
      constants: experimentConstants(),
    };
  }

  // -------------------------------------------------------------------------------------------
  // Create
  // -------------------------------------------------------------------------------------------

  async create(userId: string, input: CreateExperimentInput): Promise<ExperimentOut> {
    const today = todayLocal();
    this.syncFinished(userId, today);
    const handle = this.db.forUser(userId);

    const lengthDays = input.lengthDays ?? MIN_EXPERIMENT_LENGTH_DAYS;
    if (
      !Number.isInteger(lengthDays) ||
      lengthDays < MIN_EXPERIMENT_LENGTH_DAYS ||
      lengthDays > MAX_EXPERIMENT_LENGTH_DAYS
    ) {
      throw new InvalidExperimentLengthError(
        `length_days must be an integer between ${MIN_EXPERIMENT_LENGTH_DAYS} and ` +
          `${MAX_EXPERIMENT_LENGTH_DAYS}, got ${input.lengthDays}`,
      );
    }

    const activeRow = handle
      .prepare(`SELECT id FROM experiments WHERE user_id = ? AND status = 'active'`)
      .get(userId) as { id: string } | undefined;
    if (activeRow) {
      throw new ActiveExperimentExistsError('An experiment is already active.');
    }

    // The only place this module ever asks the pattern engine to compute anything — and it asks
    // to *read*, exactly what a client would see on the Insights view a moment before pressing
    // "start an experiment". No statistics are re-derived here.
    await this.patterns.recomputePatterns(userId);
    const qualifies = this.patterns
      .listPatterns(userId)
      .some(
        (pattern) =>
          pattern.kind === 'forward' &&
          pattern.status === 'active' &&
          pattern.topic === input.patternTopic &&
          pattern.feeling === input.patternFeeling,
      );
    if (!qualifies) {
      throw new NonQualifyingPatternError(
        `"${input.patternTopic}" / "${input.patternFeeling}" is not a currently qualifying ` +
          `pattern — it must appear as an active forward pattern in /insights before an ` +
          `experiment can be started on it.`,
      );
    }

    const startDate = input.startDate ?? today;
    const endDate = addDays(startDate, lengthDays - 1);
    const id = randomUUID();
    const createdAt = encodeDateTime(nowUtc());

    handle
      .prepare(
        `INSERT INTO experiments
           (id, user_id, pattern_topic, pattern_feeling, hypothesis_kind, start_date, end_date,
            status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?)`,
      )
      .run(
        id,
        userId,
        input.patternTopic,
        input.patternFeeling,
        input.hypothesisKind,
        encodeDate(startDate),
        encodeDate(endDate),
        createdAt,
      );

    return this.toOut(this.mustFind(userId, id));
  }

  // -------------------------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------------------------

  getActive(userId: string): ExperimentOut {
    this.syncFinished(userId, todayLocal());
    const row = this.db
      .forUser(userId)
      .prepare(`SELECT * FROM experiments WHERE user_id = ? AND status = 'active'`)
      .get(userId) as ExperimentRow | undefined;
    if (!row) throw new NoActiveExperimentError('No experiment is currently active.');
    return this.toOut(row);
  }

  private mustFind(userId: string, id: string): ExperimentRow {
    const row = this.db
      .forUser(userId)
      .prepare('SELECT * FROM experiments WHERE id = ? AND user_id = ?')
      .get(id, userId) as ExperimentRow | undefined;
    if (!row) throw new ExperimentNotFoundError(`No experiment with id ${id}.`);
    return row;
  }

  // -------------------------------------------------------------------------------------------
  // Abandon
  // -------------------------------------------------------------------------------------------

  abandon(userId: string, id: string): ExperimentOut {
    this.syncFinished(userId, todayLocal());
    const row = this.mustFind(userId, id);
    if (row.status !== 'active') {
      throw new ExperimentNotActiveError(
        `Experiment ${id} is ${row.status}, not active, and cannot be abandoned.`,
      );
    }
    this.db
      .forUser(userId)
      .prepare(`UPDATE experiments SET status = 'abandoned' WHERE id = ? AND user_id = ?`)
      .run(id, userId);
    return this.toOut(this.mustFind(userId, id));
  }

  // -------------------------------------------------------------------------------------------
  // Results
  // -------------------------------------------------------------------------------------------

  results(userId: string, id: string): ExperimentResultsOut {
    this.syncFinished(userId, todayLocal());
    const row = this.mustFind(userId, id);
    const experimentOut = this.toOut(row);

    const start = decodeDate(row.start_date);
    const end = decodeDate(row.end_date);
    const today = todayLocal();

    const experimentRange = elapsedWindow(start, end, today);
    const experimentDays = windowLengthDays(experimentRange.start, experimentRange.end);
    const baselineRange = baselineWindowFor(start, experimentDays);

    const topicId = this.db
      .forUser(userId)
      .prepare('SELECT id FROM topics WHERE user_id = ? AND name = ?')
      .get(userId, row.pattern_topic) as { id: string } | undefined;

    const experimentAssoc = windowAssociation(
      this.windowCounts(
        userId,
        topicId?.id ?? null,
        row.pattern_feeling,
        experimentRange.start,
        experimentRange.end,
      ),
      experimentRange.start,
      experimentRange.end,
    );
    const baselineAssoc = windowAssociation(
      this.windowCounts(
        userId,
        topicId?.id ?? null,
        row.pattern_feeling,
        baselineRange.start,
        baselineRange.end,
      ),
      baselineRange.start,
      baselineRange.end,
    );

    const { verdictText, insufficientData } = experimentVerdict(
      row.pattern_topic,
      row.pattern_feeling,
      experimentAssoc,
      baselineAssoc,
    );

    return {
      experiment: experimentOut,
      experiment_window: toWindowOut(experimentAssoc),
      baseline_window: toWindowOut(baselineAssoc),
      verdict_text: verdictText,
      insufficient_data: insufficientData,
      constants: experimentConstants(),
    };
  }

  /**
   * One window's raw counts: entries with/without the topic, and among each, with/without the
   * feeling — plus how many distinct days the topic was mentioned on. Confined to entries whose
   * feeling the user actually confirmed, exactly like every other count in the engine (C-04);
   * "observation only" (module docstring) means this reads that same evidence, never a different
   * or looser set of it.
   */
  private windowCounts(
    userId: string,
    topicId: string | null,
    feelingKey: string,
    start: PlainDate,
    end: PlainDate,
  ): WindowCounts {
    const placeholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT e.entry_date,
                CASE WHEN et.entry_id IS NOT NULL THEN 1 ELSE 0 END AS has_topic,
                CASE WHEN ef.entry_id IS NOT NULL THEN 1 ELSE 0 END AS has_feeling
         FROM diary_entries e
         LEFT JOIN entry_topics et ON et.entry_id = e.id AND et.topic_id = ? AND et.user_id = ?
         LEFT JOIN entry_feelings ef ON ef.entry_id = e.id AND ef.feeling_key = ? AND ef.user_id = ?
         WHERE e.user_id = ? AND e.feeling_source IN (${placeholders})
           AND e.entry_date >= ? AND e.entry_date <= ?`,
      )
      .all(
        topicId ?? '',
        userId,
        feelingKey,
        userId,
        userId,
        ...CONFIRMED_FEELING_SOURCES,
        encodeDate(start),
        encodeDate(end),
      ) as Array<{
      entry_date: string;
      has_topic: number;
      has_feeling: number;
    }>;

    let presentCount = 0;
    let presentTotal = 0;
    let absentCount = 0;
    let absentTotal = 0;
    const topicDays = new Set<string>();

    for (const row of rows) {
      if (row.has_topic) {
        presentTotal += 1;
        topicDays.add(row.entry_date);
        if (row.has_feeling) presentCount += 1;
      } else {
        absentTotal += 1;
        if (row.has_feeling) absentCount += 1;
      }
    }

    return { presentCount, presentTotal, absentCount, absentTotal, daysWithTopic: topicDays.size };
  }
}

function toWindowOut(assoc: WindowAssociation): WindowOut {
  return {
    start_date: serializeDate(assoc.start),
    end_date: serializeDate(assoc.end),
    total_days: assoc.totalDays,
    days_with_topic: assoc.daysWithTopic,
    present_count: assoc.presentCount,
    present_total: assoc.presentTotal,
    absent_count: assoc.absentCount,
    absent_total: assoc.absentTotal,
    present_rate: assoc.presentRate,
    absent_rate: assoc.absentRate,
  };
}
