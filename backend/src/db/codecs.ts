/**
 * The single place any value crosses into or out of storage or the wire.
 *
 * SQLite has no date, boolean or JSON type, so these columns hold text and integers in a specific
 * shape. That shape is already written into every existing diary, which makes reproducing it a
 * requirement (FR-020/FR-022) rather than a style choice — this is compatibility with *data*, not
 * with any particular implementation. Nothing else may call `toISOString()`, `JSON.stringify` on a
 * stored column, or pass a raw boolean to SQLite.
 *
 * See data-model.md "Value encoding" and research.md §1.
 */

/**
 * A naive wall-clock instant with microsecond precision.
 *
 * Deliberately not a `Date`: `Date` is millisecond-resolution and carries an implicit UTC epoch,
 * so it cannot represent `…248359` and cannot represent "naive" at all. Storing through a `Date`
 * silently truncates every timestamp the diary has.
 */
export interface NaiveDateTime {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  second: number;
  /** 0–999999. Six digits, always. */
  microsecond: number;
}

export interface PlainDate {
  year: number;
  month: number; // 1-12
  day: number;
}

const pad = (value: number, width: number): string => String(value).padStart(width, '0');

// ---------------------------------------------------------------------------------------------
// Datetime
// ---------------------------------------------------------------------------------------------

const DATETIME_PATTERN = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$/;

export function decodeDateTime(stored: string): NaiveDateTime {
  const match = DATETIME_PATTERN.exec(stored.trim());
  if (!match) {
    throw new Error(`Unrecognised datetime in the diary: ${JSON.stringify(stored)}`);
  }
  const [, year, month, day, hour, minute, second, fraction] = match;
  return {
    year: Number(year),
    month: Number(month),
    day: Number(day),
    hour: Number(hour),
    minute: Number(minute),
    second: Number(second),
    // A stored value may carry fewer than six digits; pad on the right.
    microsecond: fraction ? Number(fraction.padEnd(6, '0')) : 0,
  };
}

/** Storage form: `YYYY-MM-DD HH:MM:SS.ffffff` — space separator, six digits, no zone. */
export function encodeDateTime(value: NaiveDateTime): string {
  return (
    `${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)} ` +
    `${pad(value.hour, 2)}:${pad(value.minute, 2)}:${pad(value.second, 2)}.` +
    `${pad(value.microsecond, 6)}`
  );
}

/** Wire form: the same, with a `T` separator and still no timezone designator. */
export function serializeDateTime(value: NaiveDateTime): string {
  return encodeDateTime(value).replace(' ', 'T');
}

// ---------------------------------------------------------------------------------------------
// Date
// ---------------------------------------------------------------------------------------------

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export function decodeDate(stored: string): PlainDate {
  const match = DATE_PATTERN.exec(stored.trim());
  if (!match) {
    throw new Error(`Unrecognised date in the diary: ${JSON.stringify(stored)}`);
  }
  return { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
}

export function encodeDate(value: PlainDate): string {
  return `${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)}`;
}

/** Wire form is identical to storage form for plain dates. */
export const serializeDate = encodeDate;

// ---------------------------------------------------------------------------------------------
// JSON columns
// ---------------------------------------------------------------------------------------------

/**
 * The stored JSON shape differs from `JSON.stringify` in two ways that both fail silently:
 *
 *  1. **Separators.** Stored rows use `", "` and `": "`; `JSON.stringify` writes `","` and `":"`.
 *     A row written the compact way is a different byte sequence from every other row.
 *  2. **Non-ASCII is escaped** as `\uXXXX` — `café` becomes `caf\u00e9`. `JSON.stringify` emits the
 *     character literally. Easy to miss, because seeded data is pure ASCII while topic names come
 *     from whatever the user writes.
 *
 * Built by walking the value rather than post-processing `JSON.stringify` output: a regex over the
 * serialized string cannot tell a separator from the characters `", "` inside a string literal.
 */
export function encodeJson(value: unknown): string {
  return writeJson(value);
}

function writeJson(value: unknown): string {
  if (value === null || value === undefined) return 'null';

  switch (typeof value) {
    case 'string':
      return writeJsonString(value);
    case 'number':
      return Number.isFinite(value) ? String(value) : 'null';
    case 'boolean':
      return value ? 'true' : 'false';
    default:
      break;
  }

  if (Array.isArray(value)) {
    return `[${value.map(writeJson).join(', ')}]`;
  }

  const entries = Object.entries(value as Record<string, unknown>).filter(
    ([, v]) => v !== undefined,
  );
  return `{${entries.map(([k, v]) => `${writeJsonString(k)}: ${writeJson(v)}`).join(', ')}}`;
}

/** JSON string literal with all non-ASCII escaped. */
function writeJsonString(value: string): string {
  let out = '"';
  for (const char of value) {
    const code = char.codePointAt(0)!;
    switch (char) {
      case '"':
        out += '\\"';
        continue;
      case '\\':
        out += '\\\\';
        continue;
      case '\n':
        out += '\\n';
        continue;
      case '\r':
        out += '\\r';
        continue;
      case '\t':
        out += '\\t';
        continue;
      case '\b':
        out += '\\b';
        continue;
      case '\f':
        out += '\\f';
        continue;
      default:
        break;
    }
    if (code < 0x20 || code > 0x7e) {
      // Astral characters escape as a surrogate pair, as the JSON spec requires.
      if (code > 0xffff) {
        const adjusted = code - 0x10000;
        const high = 0xd800 + (adjusted >> 10);
        const low = 0xdc00 + (adjusted & 0x3ff);
        out += `\\u${high.toString(16).padStart(4, '0')}\\u${low.toString(16).padStart(4, '0')}`;
      } else {
        out += `\\u${code.toString(16).padStart(4, '0')}`;
      }
      continue;
    }
    out += char;
  }
  return `${out}"`;
}

export function decodeJson<T>(stored: string): T {
  return JSON.parse(stored) as T;
}

// ---------------------------------------------------------------------------------------------
// Booleans
// ---------------------------------------------------------------------------------------------

export function encodeBool(value: boolean): 0 | 1 {
  return value ? 1 : 0;
}

export function decodeBool(stored: number | bigint | boolean): boolean {
  return Boolean(Number(stored));
}

// ---------------------------------------------------------------------------------------------
// Clock sources
// ---------------------------------------------------------------------------------------------

/**
 * UTC wall clock, used for `created_at` / `updated_at`.
 *
 * Node has no microsecond clock. `Date` gives milliseconds, so the final three digits are derived
 * from `process.hrtime.bigint()` — the stored value must be six digits wide, and a timestamp always
 * ending `000` would be a visible tell that the port is lossy.
 */
export function nowUtc(): NaiveDateTime {
  const now = new Date();
  const subMilli = Number(process.hrtime.bigint() % 1_000_000n) / 1000;
  return {
    year: now.getUTCFullYear(),
    month: now.getUTCMonth() + 1,
    day: now.getUTCDate(),
    hour: now.getUTCHours(),
    minute: now.getUTCMinutes(),
    second: now.getUTCSeconds(),
    microsecond: now.getUTCMilliseconds() * 1000 + (Math.floor(subMilli) % 1000),
  };
}

/**
 * The server's **local** calendar date, used for `entry_date`.
 *
 * This deliberately disagrees with `nowUtc()` on a machine not running UTC. Every entry already in
 * the diary was filed under this rule, and day grouping, the monthly calendar and the daily average
 * all key off it — unifying the two clocks during a port would silently re-file existing entries
 * (research.md §3). It is a latent defect, reproduced on purpose, with its own follow-up.
 *
 * `simulatedUtcOffsetMinutes` exists only for #125's regression test (`tests/helpers/
 * dates.test.ts`), which needs to reproduce the local/UTC disagreement deterministically under
 * `TZ=UTC` — the timezone CI actually runs in, where the real disagreement cannot occur. Actually
 * reassigning `process.env.TZ` at runtime was tried first and rejected: this suite's Vitest pool
 * runs every file in one worker thread (`vitest.config.mts`), and a worker thread's `Date` reads
 * the OS timezone once at thread start — a later `process.env.TZ` write in the same thread is
 * silently ignored, which would make the regression test assert nothing while looking like it
 * pins a timezone. No real caller passes this parameter; the local date the server actually files
 * entries under always comes from the process's real timezone, exactly as before.
 */
export function todayLocal(simulatedUtcOffsetMinutes?: number): PlainDate {
  if (simulatedUtcOffsetMinutes !== undefined) {
    const shifted = new Date(Date.now() + simulatedUtcOffsetMinutes * 60_000);
    return {
      year: shifted.getUTCFullYear(),
      month: shifted.getUTCMonth() + 1,
      day: shifted.getUTCDate(),
    };
  }
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() };
}
