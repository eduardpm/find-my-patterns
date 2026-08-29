import type { FeelingKey } from '../db/feeling-vocabulary';

/**
 * Daylio's five default moods → this app's feeling vocabulary (L-1b, #35).
 *
 * **Why only five entries.** Daylio's `mood` column is free text: the five default mood names can
 * be renamed per-installation, and a user may add further custom moods inside any of the five
 * groups (confirmed by https://daylio-parser.readthedocs.io/en/latest/config.html and corroborated
 * by community write-ups — "the default Daylio setup includes just 5 moods, called awful, bad,
 * meh, good, rad", all "customizable into other names"). The exported CSV has no column naming
 * which of the five groups a custom mood belongs to, so this backend has no honest way to place a
 * renamed or custom mood anywhere on the scale. Per the constitution-level rule this ticket is
 * built against (`specs/research/improvement-opportunities.md` §8: "mapped conservatively... never
 * silently treated as evidence the user didn't see"), a mood this table does not recognise by its
 * exact default English name is **skipped and reported**, never guessed at.
 *
 * **The mapping itself**, chosen against the feeling vocabulary as it stands after #60 (valence
 * lives per-feeling, not per-group — see `db/feeling-vocabulary.ts`):
 *
 *  - `rad`   → `happy`      (Uplifted, positive) — Daylio's best rung maps to the plainest positive
 *              feeling in the vocabulary's own best group.
 *  - `good`  → `content`    (Steady, positive per #60) — a good-but-not-euphoric day; `content` is
 *              exactly that register and, unlike `neutral`, does not collapse two different
 *              Daylio rungs onto one feeling.
 *  - `meh`   → `neutral`    (Steady, neutral) — Daylio's own middle rung is literally "neither
 *              good nor bad", which is `neutral`'s definition in this vocabulary too.
 *  - `bad`   → `sad`        (Low, negative) — the plainest negative feeling for Daylio's
 *              second-worst rung.
 *  - `awful` → `depressed`  (Low, negative) — Daylio's worst rung. The issue's own suggestion
 *              (`awful → miserable`) names a feeling that does not exist in this vocabulary
 *              (the Low group is `sad, depressed, lonely, disappointed, hopeless, numb, sleepy,
 *              exhausted` — no `miserable`); `depressed` is the closest severity match for "the
 *              worst a day can be" and is proposed here in `miserable`'s place. **Flagged in the
 *              PR for review** — this is the one mapping that is a genuine judgment call rather
 *              than a near-synonym.
 *
 * Every mapped feeling key is checked at compile time against `FeelingKey`, so a future vocabulary
 * change that removes one of these five keys fails the build here rather than silently mapping a
 * Daylio mood onto nothing.
 *
 * Source for the column layout and the five default names, retrieved 2026-08-29:
 *  - https://github.com/MichaelCurrin/daylio-csv-parser/blob/master/docs/csv-format.md
 *  - https://github.com/MichaelCurrin/daylio-csv-parser/blob/master/dayliopy/sample.csv (a real
 *    export file — see `tests/fixtures/daylio-sample.csv`, adapted from it)
 *  - https://daylio-parser.readthedocs.io/en/latest/config.html
 */
export const DAYLIO_MOOD_MAP: Record<string, FeelingKey> = {
  rad: 'happy',
  good: 'content',
  meh: 'neutral',
  bad: 'sad',
  awful: 'depressed',
};

/** Case- and whitespace-insensitive: Daylio's own sample export carries trailing spaces on `mood`. */
export function normalizeDaylioMood(raw: string): string {
  return raw.trim().toLowerCase();
}

/** `null` means "not one of the five defaults" — the caller's job is to skip and report that row. */
export function mapDaylioMood(raw: string): FeelingKey | null {
  return DAYLIO_MOOD_MAP[normalizeDaylioMood(raw)] ?? null;
}
