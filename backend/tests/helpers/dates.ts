/**
 * Calendar-date test helpers, one per clock the server itself exposes (`src/db/codecs.ts`):
 * `localDateString` mirrors `todayLocal()` (used for `entry_date`), `utcDateString` mirrors
 * `nowUtc()` (used for `created_at`/`updated_at`).
 *
 * #125 was a test comparing a value written by one clock against a date computed from the other.
 * The two clocks agree on every day except the window between local midnight and UTC midnight
 * (roughly 22:00–00:00 UTC in CEST), so the mismatch passed every review and every CI run — CI
 * runs in UTC, where the two clocks can never disagree — and only broke on a developer's machine,
 * at night. Naming the clock at the call site (`utcDateString(0)`, not a bare `new Date()` or an
 * unqualified `dateString(0)`) makes the choice something an author has to get right on purpose
 * rather than something that happens to work until the window opens.
 *
 * Both compute the offset through the `Date` object's own field setters (`setDate`/`setUTCDate`)
 * rather than by adding `offsetDays * 86_400_000` milliseconds to `Date.now()`: a calendar day is
 * not always 86,400,000 ms in a zone that observes DST, so millisecond arithmetic silently mis-dates
 * an entry backdated across a DST transition, while `setDate`/`setUTCDate` roll the calendar field
 * over correctly — including across a month or year boundary — because that is what they are for.
 */

/** The server's local calendar date, offset by `offsetDays` (negative for the past). Matches `todayLocal()`. */
export function localDateString(offsetDays: number): string {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** The UTC calendar date, offset by `offsetDays` (negative for the past). Matches `nowUtc()`. */
export function utcDateString(offsetDays: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offsetDays);
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
