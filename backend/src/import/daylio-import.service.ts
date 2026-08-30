import { Inject, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { encodeDate, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import type { PlainDate } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import type { FeelingKey } from '../db/feeling-vocabulary';
import { EntriesService } from '../entries/entries.service';
import { TopicsService } from '../topics/topics.service';
import { DAYLIO_MOOD_MAP, mapDaylioMood, normalizeDaylioMood } from './daylio-mood-map';
import { interpretDaylioRow, parseDaylioCsv, type DaylioParsedRow } from './daylio-csv-parser';

/**
 * The Daylio CSV two-phase import (L-1b, #35): `dry-run` builds a report and never writes;
 * `commit` re-derives the identical report, checks it against the one the caller says it accepted,
 * and only then writes. Both phases share `buildReport` so there is exactly one place that decides
 * what a given file means — `commit` cannot silently disagree with the report a client already saw.
 */

/** The submitted `report_hash` does not match a fresh dry-run of this exact file. */
export class DaylioReportHashMismatchError extends Error {}

/**
 * `csv_imports.content_hash` is still a bare, globally-unique primary key (`schema.ts`'s M-1b
 * note names this as a real, deliberately-deferred multi-tenant defect: fixing it means rebuilding
 * the table's key to `(user_id, content_hash)`, which belongs in its own reviewable, migration-
 * tested PR rather than folded into this already-large one). The practical consequence: two
 * different accounts can never both import the same byte-identical export.
 *
 * Before this ticket, that showed up as a *silent* no-op for whichever account imported second —
 * `buildReport`'s `alreadyImported` check unfiltered by owner would tell a second account "this was
 * already imported," which is a false claim about *their* diary. Filtering that check by `user_id`
 * (below) removes the false claim, but exposes the real one: a second account's dry-run correctly
 * says "never imported," and its commit then collides with the first account's row on the bare
 * primary key. This error turns that collision into an honest, catchable failure instead of an
 * unhandled 500 — a real improvement within this ticket's scope, though not the actual fix, which
 * is the follow-up ticket the PR description names.
 */
export class DaylioContentHashCollisionError extends Error {}

export interface MoodMappingEntry {
  daylioMood: string;
  feelingKey: FeelingKey;
}

export interface UnmappedMood {
  mood: string;
  count: number;
  /** A sample, not the full list — capped so one wildly custom diary cannot balloon the report. */
  rowNumbers: number[];
}

export interface RowError {
  rowNumber: number;
  reason: string;
}

export interface CollisionEntry {
  rowNumber: number;
  entryDate: string;
  reason: string;
}

export interface PreviousImport {
  importedAt: string;
  entryCount: number;
}

export interface DaylioDryRunReport {
  contentHash: string;
  reportHash: string;
  totalRows: number;
  parseableCount: number;
  unparseableRows: RowError[];
  moodMapping: MoodMappingEntry[];
  unmappedMoods: UnmappedMood[];
  dateRange: { start: string; end: string } | null;
  collisions: CollisionEntry[];
  /** Rows that would actually be written on commit: parseable, mapped — mood mapping is the one
   *  thing that is ever allowed to drop a row; a collision does not (see `commit`'s doc comment). */
  importableCount: number;
  alreadyImported: boolean;
  previousImport?: PreviousImport;
}

export interface DaylioCommitResult {
  idempotent: boolean;
  importedCount: number;
  skippedUnmappedCount: number;
  entryIds: string[];
  contentHash: string;
  previousImport?: PreviousImport;
}

const MAX_UNMAPPED_ROW_SAMPLES = 10;

function sha256Hex(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}

function compareDates(a: PlainDate, b: PlainDate): number {
  if (a.year !== b.year) return a.year - b.year;
  if (a.month !== b.month) return a.month - b.month;
  return a.day - b.day;
}

/** `note_title` + `note` → `raw_text`. Neither field is in the issue's literal mapping list, but
 *  dropping a title the user actually typed would be exactly the silent data loss this feature
 *  exists to avoid — see the PR description. */
function composeRawText(noteTitle: string, note: string): string {
  if (noteTitle && note) return `${noteTitle}\n\n${note}`;
  return noteTitle || note;
}

interface ImportableRow {
  row: DaylioParsedRow;
  feelingKey: FeelingKey;
}

@Injectable()
export class DaylioImportService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly entries: EntriesService,
    private readonly topics: TopicsService,
  ) {}

  /**
   * Parses, maps and reports on a file — the whole of what `dry-run` does, and the first half of
   * what `commit` does. Never writes to `diary_entries`; `commit` is the only place that does.
   */
  private buildReport(
    userId: string,
    buffer: Buffer,
  ): {
    report: DaylioDryRunReport;
    importable: ImportableRow[];
  } {
    const handle = this.db.forUser(userId);
    const contentHash = sha256Hex(buffer);
    const text = buffer.toString('utf-8');

    // A structurally wrong file (bad header, empty upload) throws — see parseDaylioCsv's doc
    // comment for why that is not reported per row.
    const rawRows = parseDaylioCsv(text);

    const unparseableRows: RowError[] = [];
    const parsedRows: DaylioParsedRow[] = [];
    for (const raw of rawRows) {
      try {
        parsedRows.push(interpretDaylioRow(raw));
      } catch (err) {
        unparseableRows.push({
          rowNumber: raw.rowNumber,
          reason: err instanceof Error ? err.message : String(err),
        });
      }
    }

    const unmapped = new Map<string, { count: number; rowNumbers: number[] }>();
    const mappedMoodsSeen = new Set<string>();
    const importable: ImportableRow[] = [];

    for (const row of parsedRows) {
      const feelingKey = mapDaylioMood(row.moodRaw);
      const normalizedMood = normalizeDaylioMood(row.moodRaw);
      if (feelingKey === null) {
        // Conservative mapping (L-1b): a mood this table does not recognise is skipped and
        // reported — never guessed at. This is the one rule in this file that is constitution-
        // level rather than a judgment call.
        const entry = unmapped.get(normalizedMood) ?? { count: 0, rowNumbers: [] };
        entry.count += 1;
        if (entry.rowNumbers.length < MAX_UNMAPPED_ROW_SAMPLES)
          entry.rowNumbers.push(row.rowNumber);
        unmapped.set(normalizedMood, entry);
        continue;
      }
      mappedMoodsSeen.add(normalizedMood);
      importable.push({ row, feelingKey });
    }

    // A collision is informational, not a reason to drop a row (see `commit`'s doc comment): an
    // entry sharing an existing one's date and exact text, most often a file imported twice under
    // two different names, or a second export that overlaps the first one's date range.
    const collisions: CollisionEntry[] = [];
    for (const { row } of importable) {
      const rawText = composeRawText(row.noteTitle, row.note);
      const existing = handle
        .prepare(
          'SELECT 1 FROM diary_entries WHERE user_id = ? AND entry_date = ? AND raw_text = ? LIMIT 1',
        )
        .get(userId, encodeDate(row.entryDate), rawText);
      if (existing !== undefined) {
        collisions.push({
          rowNumber: row.rowNumber,
          entryDate: encodeDate(row.entryDate),
          reason: 'An entry with this date and text already exists in the diary.',
        });
      }
    }

    const moodMapping: MoodMappingEntry[] = [...mappedMoodsSeen]
      .sort()
      .map((daylioMood) => ({ daylioMood, feelingKey: DAYLIO_MOOD_MAP[daylioMood] }));
    const unmappedMoods: UnmappedMood[] = [...unmapped.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([mood, value]) => ({ mood, count: value.count, rowNumbers: value.rowNumbers }));

    let dateRange: { start: string; end: string } | null = null;
    if (parsedRows.length > 0) {
      let min = parsedRows[0].entryDate;
      let max = parsedRows[0].entryDate;
      for (const row of parsedRows) {
        if (compareDates(row.entryDate, min) < 0) min = row.entryDate;
        if (compareDates(row.entryDate, max) > 0) max = row.entryDate;
      }
      dateRange = { start: encodeDate(min), end: encodeDate(max) };
    }

    const sortedUnparseableRows = [...unparseableRows].sort((a, b) => a.rowNumber - b.rowNumber);
    const sortedCollisions = [...collisions].sort((a, b) => a.rowNumber - b.rowNumber);

    // `reportHash` is hashed over only what the *file itself* (plus the mood-mapping vocabulary
    // currently in force) determines — never `collisions`, `alreadyImported` or `previousImport`.
    // Both of those depend on what else is already in the diary at the moment `buildReport` runs,
    // which a commit itself changes: hashing them in would make committing the very file that was
    // just accepted change its own hash on the next call, and the reportHash comparison at the top
    // of `commit` would then reject a second, idempotency-checking commit of the exact same file as
    // a "different" report. Reproducibility across repeated calls to the same file is the one thing
    // this hash exists for.
    const hashedFields = {
      contentHash,
      totalRows: rawRows.length,
      parseableCount: parsedRows.length,
      unparseableRows: sortedUnparseableRows,
      moodMapping,
      unmappedMoods,
      dateRange,
      importableCount: importable.length,
    };
    const reportHash = sha256Hex(Buffer.from(JSON.stringify(hashedFields), 'utf-8'));

    const reportCore = { ...hashedFields, collisions: sortedCollisions };

    // Filtered by `user_id`, per this method's own doc comment on `DaylioContentHashCollisionError`:
    // whether *this account* already imported this exact file, never whether some other account
    // did.
    const previousRow = handle
      .prepare(
        'SELECT imported_at, entry_count FROM csv_imports WHERE user_id = ? AND content_hash = ?',
      )
      .get(userId, contentHash) as { imported_at: string; entry_count: number } | undefined;
    const previousImport: PreviousImport | undefined = previousRow
      ? { importedAt: previousRow.imported_at, entryCount: Number(previousRow.entry_count) }
      : undefined;

    return {
      report: {
        ...reportCore,
        reportHash,
        alreadyImported: previousRow !== undefined,
        previousImport,
      },
      importable,
    };
  }

  /** Parses and reports on a file. Never writes. */
  dryRun(userId: string, buffer: Buffer): DaylioDryRunReport {
    return this.buildReport(userId, buffer).report;
  }

  /**
   * Writes the entries a dry-run of this exact file would report as importable.
   *
   * Two guards, in order:
   *
   *  1. **`reportHash` must match.** `commit` re-parses the file and rebuilds the report itself —
   *     it never trusts a report a client remembers — and refuses to write if what it just
   *     computed disagrees with what the caller says it accepted. This is what keeps "the same
   *     file the dry-run report described" true even if the mood-mapping table or the entry's own
   *     vocabulary has changed between the two calls.
   *  2. **`content_hash` must be new.** A file already recorded in `csv_imports` writes nothing
   *     and answers `idempotent: true` — re-posting the exact same export can never double-import,
   *     which is the one thing a diary import absolutely cannot get wrong.
   *
   * A **collision** (an existing entry with the same date and text) is reported by the dry-run but
   * does not block a row here — the issue's idempotency requirement is about *the file*, not about
   * a coincidence with entries written some other way, and silently dropping a row a person could
   * see in the report and chose to commit anyway would be a worse surprise than an occasional
   * duplicate they can see and delete.
   */
  commit(userId: string, buffer: Buffer, reportHash: string): DaylioCommitResult {
    const { report, importable } = this.buildReport(userId, buffer);

    if (report.reportHash !== reportHash) {
      throw new DaylioReportHashMismatchError(
        'report_hash does not match a fresh dry-run of this file. Run dry-run again and commit ' +
          'the report it returns.',
      );
    }

    if (report.alreadyImported) {
      return {
        idempotent: true,
        importedCount: 0,
        skippedUnmappedCount: sumUnmapped(report),
        entryIds: [],
        contentHash: report.contentHash,
        previousImport: report.previousImport,
      };
    }

    const handle = this.db.forUser(userId);

    // The whole write — every entry, every topic link, and the `csv_imports` row that marks the
    // file done — is one transaction. better-sqlite3 nests `EntriesService.createImportedEntry`'s
    // own transaction inside this one via a savepoint, so a failure partway through a large import
    // rolls the entire commit back rather than leaving some entries written and the file still
    // unmarked — which is exactly the state a retry could turn into a double-import.
    let entryIds: string[];
    try {
      entryIds = handle.transaction((): string[] => {
        const ids: string[] = [];
        for (const { row, feelingKey } of importable) {
          const entry = this.entries.createImportedEntry(userId, {
            rawText: composeRawText(row.noteTitle, row.note),
            entryDate: row.entryDate,
            createdAt: row.createdAt,
            feelingKey,
            origin: 'daylio_import',
          });
          ids.push(entry.id);
          if (row.activities.length > 0) {
            // 'import' (L-1b, #35): a Daylio activity tag, not text a keyword scan found — see
            // TopicsService.linkTopics's doc comment for why this must not be 'keyword'.
            this.topics.linkTopics(userId, entry.id, row.activities, 'import');
          }
        }

        handle
          .prepare(
            `INSERT INTO csv_imports (content_hash, user_id, source, imported_at, entry_count,
             report_json)
             VALUES (?, ?, 'daylio', ?, ?, ?)`,
          )
          .run(
            report.contentHash,
            userId,
            encodeDateTime(nowUtc()),
            ids.length,
            encodeJson(report),
          );

        return ids;
      });
    } catch (error) {
      // See `DaylioContentHashCollisionError`'s doc comment: `csv_imports.content_hash` is still a
      // bare, global primary key, so a different account committing this exact file first collides
      // here rather than being caught by the (correctly per-user-scoped) `alreadyImported` check
      // above.
      if (
        error instanceof Error &&
        /UNIQUE constraint failed: csv_imports\.content_hash/.test(error.message)
      ) {
        throw new DaylioContentHashCollisionError(
          'This exact file was already imported by a different account. Per-account import ' +
            'history for identical files is a known limitation, tracked separately.',
        );
      }
      throw error;
    }

    return {
      idempotent: false,
      importedCount: entryIds.length,
      skippedUnmappedCount: sumUnmapped(report),
      entryIds,
      contentHash: report.contentHash,
    };
  }
}

function sumUnmapped(report: DaylioDryRunReport): number {
  return report.unmappedMoods.reduce((sum, mood) => sum + mood.count, 0);
}
