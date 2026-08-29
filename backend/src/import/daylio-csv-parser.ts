import type { NaiveDateTime, PlainDate } from '../db/codecs';

/**
 * Parsing for the Daylio CSV export (L-1b, #35).
 *
 * Pure and dependency-free — no CSV library is in `package.json`, and RFC 4180 quoting (the only
 * thing this format actually needs: quoted fields that may embed commas, newlines and doubled
 * quotes) is a small, self-contained state machine that does not warrant a new dependency for one
 * importer.
 *
 * The column layout — `full_date,date,weekday,time,mood,activities,note_title,note`, activities
 * pipe-separated, text fields quoted — is verified against a real export file, not guessed. See
 * `daylio-mood-map.ts`'s doc comment for the sources, and `tests/fixtures/daylio-sample.csv` for
 * the fixture adapted from one of them.
 */

export const DAYLIO_CSV_HEADER = [
  'full_date',
  'date',
  'weekday',
  'time',
  'mood',
  'activities',
  'note_title',
  'note',
] as const;

/** The file itself is not a Daylio export — wrong header, unreadable quoting, or empty. */
export class DaylioCsvFormatError extends Error {}

/** One data row, still as the raw strings the CSV carried — nothing here has been interpreted yet. */
export interface DaylioCsvRow {
  /** 1-based, counting data rows only (the header is row 0 and is never included here). */
  rowNumber: number;
  fullDate: string;
  time: string;
  mood: string;
  activities: string;
  noteTitle: string;
  note: string;
}

/**
 * Splits raw CSV text into a header-checked list of data rows.
 *
 * Structural problems throw — a file that is not shaped like a Daylio export at all (wrong
 * columns, an empty upload) cannot produce a meaningful per-row report, so the caller answers 422
 * rather than a report saying "0 of 0 rows parseable". A malformed individual *value* (an
 * unreadable date, say) is a different kind of problem and does not throw here — see
 * `interpretDaylioRow`, which reports it per row instead.
 */
export function parseDaylioCsv(text: string): DaylioCsvRow[] {
  const table = parseCsvTable(text);
  if (table.length === 0) {
    throw new DaylioCsvFormatError('The file is empty.');
  }

  const header = table[0].map((cell) => cell.trim().toLowerCase());
  const headerMatches =
    header.length === DAYLIO_CSV_HEADER.length &&
    DAYLIO_CSV_HEADER.every((name, index) => header[index] === name);
  if (!headerMatches) {
    throw new DaylioCsvFormatError(
      `Unrecognised column layout. Expected "${DAYLIO_CSV_HEADER.join(',')}", got "${table[0].join(',')}".`,
    );
  }

  const rows: DaylioCsvRow[] = [];
  for (let i = 1; i < table.length; i += 1) {
    const cells = table[i];
    // A wholly blank trailing line (common when a file ends with an extra newline) parses as a
    // single empty cell — that is a formatting artefact, not a data row, and is silently dropped.
    if (cells.length === 1 && cells[0].trim() === '') continue;
    if (cells.length !== DAYLIO_CSV_HEADER.length) {
      throw new DaylioCsvFormatError(
        `Row ${i} has ${cells.length} column(s), expected ${DAYLIO_CSV_HEADER.length}.`,
      );
    }
    rows.push({
      rowNumber: i,
      fullDate: cells[0],
      time: cells[3],
      mood: cells[4],
      activities: cells[5],
      noteTitle: cells[6],
      note: cells[7],
    });
  }
  return rows;
}

/**
 * A generic RFC 4180 table parser: quoted fields, embedded commas and newlines, `""` as an escaped
 * quote. `date` and `weekday` are read by nobody downstream — `full_date` is the one unambiguous,
 * year-bearing date column — so they are parsed like every other cell but never carried past this
 * file.
 */
function parseCsvTable(text: string): string[][] {
  // Daylio (and most spreadsheet tools) may write a leading UTF-8 BOM.
  const source = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;

  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;

  const endField = (): void => {
    row.push(field);
    field = '';
  };
  const endRow = (): void => {
    endField();
    rows.push(row);
    row = [];
  };

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    if (inQuotes) {
      if (char === '"') {
        if (source[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += char;
      }
      continue;
    }
    if (char === '"') {
      inQuotes = true;
    } else if (char === ',') {
      endField();
    } else if (char === '\r') {
      // Normalised away; the following '\n' (if any) ends the row.
    } else if (char === '\n') {
      endRow();
    } else {
      field += char;
    }
  }
  // A trailing field/row with no final newline still counts.
  if (field.length > 0 || row.length > 0) endRow();

  return rows;
}

// -------------------------------------------------------------------------------------------
// Interpreting a row's raw strings as actual values
// -------------------------------------------------------------------------------------------

export interface DaylioParsedRow {
  rowNumber: number;
  entryDate: PlainDate;
  createdAt: NaiveDateTime;
  /** Not yet mapped to a feeling — `daylio-mood-map.ts` does that, and may fail conservatively. */
  moodRaw: string;
  /** Split on `|`, trimmed, empty entries dropped — the CSV format's own convention. */
  activities: string[];
  noteTitle: string;
  note: string;
}

const FULL_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
/** `h:mm am/pm` or `hh:mm am/pm`, case-insensitive — Daylio's own sample export uses lowercase. */
const TIME_PATTERN = /^(\d{1,2}):(\d{2})\s*([ap]m)$/i;

function isRealCalendarDate(date: PlainDate): boolean {
  const asUtc = new Date(Date.UTC(date.year, date.month - 1, date.day));
  return (
    asUtc.getUTCFullYear() === date.year &&
    asUtc.getUTCMonth() === date.month - 1 &&
    asUtc.getUTCDate() === date.day
  );
}

/**
 * Interprets one raw row's `full_date` and `time` as an actual date and clock time, folds
 * `activities` into a clean list, and trims the note fields. Everything else — mood mapping,
 * feeling assignment, topic canonicalisation — happens further up the pipeline.
 *
 * Throws on a row this specific implementation cannot read (an unparseable date or time,
 * `12:61 pm`, a nonexistent calendar day). The caller collects these per row rather than letting
 * one bad line fail the whole file — see `DaylioImportService`.
 */
export function interpretDaylioRow(row: DaylioCsvRow): DaylioParsedRow {
  const dateMatch = FULL_DATE_PATTERN.exec(row.fullDate.trim());
  if (!dateMatch) {
    throw new Error(`Unrecognised full_date "${row.fullDate}" — expected YYYY-MM-DD.`);
  }
  const entryDate: PlainDate = {
    year: Number(dateMatch[1]),
    month: Number(dateMatch[2]),
    day: Number(dateMatch[3]),
  };
  if (!isRealCalendarDate(entryDate)) {
    throw new Error(`"${row.fullDate}" is not a real calendar date.`);
  }

  const timeMatch = TIME_PATTERN.exec(row.time.trim());
  if (!timeMatch) {
    throw new Error(`Unrecognised time "${row.time}" — expected "h:mm am/pm".`);
  }
  let hour = Number(timeMatch[1]);
  const minute = Number(timeMatch[2]);
  if (hour < 1 || hour > 12 || minute > 59) {
    throw new Error(`Unrecognised time "${row.time}".`);
  }
  const period = timeMatch[3].toLowerCase();
  // Daylio's 12-hour clock: 12:00 am is midnight (hour 0), 12:00 pm is noon (hour 12) — the one
  // place a 12-hour clock does not simply add 12 for "pm".
  if (period === 'am') {
    if (hour === 12) hour = 0;
  } else if (hour !== 12) {
    hour += 12;
  }

  const createdAt: NaiveDateTime = {
    year: entryDate.year,
    month: entryDate.month,
    day: entryDate.day,
    hour,
    minute,
    second: 0,
    microsecond: 0,
  };

  const activities = row.activities
    .split('|')
    .map((activity) => activity.trim())
    .filter((activity) => activity.length > 0);

  return {
    rowNumber: row.rowNumber,
    entryDate,
    createdAt,
    moodRaw: row.mood,
    activities,
    noteTitle: row.noteTitle.trim(),
    note: row.note.trim(),
  };
}
