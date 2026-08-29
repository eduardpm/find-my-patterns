/**
 * The arithmetic every new insight rests on (roadmap A3, I1, I2, I3, I5, I6).
 *
 * Pure functions, no database, no model — which is the point. Each number the user is shown has to
 * be reproducible from their own diary, and a claim that cannot be reproduced in a unit test cannot
 * be reproduced by the person reading it either.
 */

import { describe, expect, it } from 'vitest';
import {
  associationFrom,
  averageValence,
  confounderSplit,
  contextFactorsForEntry,
  contextNarrative,
  daysBetween,
  dayTypeFor,
  forwardNarrative,
  historicalNote,
  hourBlockKey,
  invert,
  inverseNarrative,
  isMixedValence,
  isPairExcluded,
  isStrong,
  percent,
  recommendationHeadlineFor,
  recommendationSentenceFor,
  seasonFor,
  suppressedByLift,
  timeOfDayBucket,
  trajectorySignal,
  weekdayIndex,
  withinWindow,
} from '../../src/insights/analysis';
import { HOUR_BLOCKS, MIN_LIFT, RECENCY_WINDOW_DAYS } from '../../src/insights/constants';

const at = (hour: number) => ({
  year: 2026,
  month: 8,
  day: 26,
  hour,
  minute: 0,
  second: 0,
  microsecond: 0,
});

describe('the recency window (I3)', () => {
  const today = { year: 2026, month: 8, day: 26 };

  it('counts whole days across a month boundary', () => {
    expect(daysBetween({ year: 2026, month: 7, day: 27 }, today)).toBe(30);
  });

  it('includes an entry one day short of the window and excludes one exactly on it', () => {
    const inside = { year: 2026, month: 7, day: 28 }; // 29 days ago
    const outside = { year: 2026, month: 7, day: 27 }; // 30 days ago
    expect(withinWindow(inside, today, RECENCY_WINDOW_DAYS)).toBe(true);
    expect(withinWindow(outside, today, RECENCY_WINDOW_DAYS)).toBe(false);
  });

  it('excludes a future date rather than treating it as very recent', () => {
    expect(withinWindow({ year: 2026, month: 9, day: 1 }, today)).toBe(false);
  });
});

describe('lift (A3)', () => {
  it('computes the ratio of the two rates — A3-SC1', () => {
    // 8 of 12 entries mentioning meetings are anxious; 3 of 28 without them are.
    const association = associationFrom(8, 12, 3, 28);
    expect(percent(association.presentRate!)).toBe(67);
    expect(percent(association.absentRate!)).toBe(11);
    expect(association.lift).toBeCloseTo(6.22, 2);
    expect(suppressedByLift(association)).toBe(false);
  });

  it('suppresses a pair that merely rides the base rate — A3-SC2', () => {
    // The topic appears in 5 tired entries out of 6, but 80% of everything is tired anyway.
    const association = associationFrom(5, 6, 19, 24);
    expect(association.lift!).toBeLessThan(MIN_LIFT);
    expect(suppressedByLift(association)).toBe(true);
  });

  it('reports no lift, and a reason, when nothing is left to compare against — A3-SC3', () => {
    const association = associationFrom(6, 6, 0, 0);
    expect(association.lift).toBeNull();
    expect(association.comparisonReason).toBe('insufficient_comparison');
  });

  it('refuses to fabricate a number when the feeling never occurs without the topic', () => {
    // A real and strong finding, but the ratio is a division by zero. Reporting it as a lift would
    // be inventing the one number A3-02 forbids inventing.
    const association = associationFrom(5, 6, 0, 20);
    expect(association.lift).toBeNull();
    expect(association.comparisonReason).toBe('no_absent_occurrences');
    // …and it is emphatically not suppressed: an un-computable lift is not a weak one.
    expect(suppressedByLift(association)).toBe(false);
  });

  it('marks a pattern strong only when the lift and the evidence both qualify (A3-07)', () => {
    const strong = associationFrom(8, 10, 2, 20); // 4x
    expect(isStrong(strong, 8)).toBe(true);
    expect(isStrong(strong, 3)).toBe(false); // same lift, too little behind it
  });

  it('inverts into the absent-side view without recomputing anything (I1-01)', () => {
    const forward = associationFrom(2, 12, 12, 16);
    const inverse = invert(forward);
    expect(inverse.presentCount).toBe(12);
    expect(inverse.presentTotal).toBe(16);
    expect(inverse.absentCount).toBe(2);
    expect(inverse.absentTotal).toBe(12);
    expect(inverse.lift!).toBeGreaterThan(MIN_LIFT);
  });
});

describe('the sentence states the numbers beside it (A3-06, I3-04)', () => {
  it('names the window in days and both rates', () => {
    const text = forwardNarrative('anxious', 'meetings', associationFrom(8, 12, 3, 28));
    expect(text).toBe(
      'You felt anxious in 8 of 12 entries mentioning meetings in the last 30 days (67%), ' +
        'and in 3 of 28 entries without it (11%).',
    );
    // I3-SC3 — the word that used to make the sentence false is gone.
    expect(text).not.toMatch(/\brecent\b/i);
  });

  it('says so plainly when the comparison could not be made (A3-05)', () => {
    expect(forwardNarrative('anxious', 'meetings', associationFrom(4, 4, 0, 0))).toContain(
      'There are not enough entries without meetings to compare.',
    );
  });

  it('phrases the inverse card as "less", never as protection (I1-04, I1-07)', () => {
    const text = inverseNarrative('sad', 'exercise', invert(associationFrom(9, 12, 4, 10)));
    expect(text).toBe(
      'You felt sad in 4 of 10 entries without exercise in the last 30 days (40%), ' +
        'and in 9 of 12 entries that mention it (75%).',
    );
    expect(text).not.toMatch(/protect|prevent|because|causes/i);
  });

  it('tells a historical pattern how long ago it was (I3-07)', () => {
    expect(historicalNote(5, 62)).toBe(
      'Last seen 62 days ago. 5 occurrences across your whole diary.',
    );
  });
});

describe('confounders (I2)', () => {
  it('annotates a collinear pair with the rate and the split — I2-SC1', () => {
    const split = confounderSplit('work', 'coffee', 9, 1, 2, 8)!;
    expect(split.coOccurrenceRate).toBeCloseTo(0.9);
    expect(split.inseparable).toBe(false);
    expect(split.note).toContain('9 of 10');
    expect(split.note).toContain('90%');
    expect(split.note).toContain('could really be about coffee');
    // I2-08: the note never claims one topic causes the other.
    expect(split.note).not.toMatch(/because|causes|due to/i);
  });

  it('says the two cannot be separated when no entry has one without the other — I2-04', () => {
    const split = confounderSplit('work', 'coffee', 10, 0, 2, 8)!;
    expect(split.inseparable).toBe(true);
    expect(split.note).toContain('cannot separate work from coffee');
  });

  it('stays quiet about topics that merely overlap', () => {
    expect(confounderSplit('work', 'coffee', 5, 5, 3, 10)).toBeNull();
  });

  // #98: bothCount must clear MIN_CONFOUNDER_CO_OCCURRENCES on its own, independent of the rate —
  // a 1-of-1 or 2-of-2 co-occurrence would otherwise pass COLLINEARITY_THRESHOLD at a rate of 1.0
  // and come back `inseparable` off a single-digit sample.
  it('rejects a 1-of-1 co-occurrence even at a perfect rate', () => {
    expect(confounderSplit('work', 'coffee', 1, 0, 0, 5)).toBeNull();
  });

  it('rejects a 2-of-2 co-occurrence even at a perfect rate', () => {
    expect(confounderSplit('work', 'coffee', 2, 0, 0, 5)).toBeNull();
  });

  it('accepts a 3-of-3 co-occurrence at the floor', () => {
    const split = confounderSplit('work', 'coffee', 3, 0, 0, 5)!;
    expect(split).not.toBeNull();
    expect(split.inseparable).toBe(true);
    expect(split.bothCount).toBe(3);
  });
});

describe('valence and time buckets (I5)', () => {
  it('averages one score per entry, not one per feeling', () => {
    // Left as one row per feeling, the three-word entry would outvote the other two.
    const average = averageValence([
      { valences: ['negative', 'negative', 'negative'] },
      { valences: ['positive'] },
      { valences: ['positive'] },
    ]);
    expect(average).toBeCloseTo((-1 + 1 + 1) / 3);
  });

  it('has nothing to say about entries carrying no known valence', () => {
    expect(averageValence([{ valences: [] }])).toBeNull();
  });

  it('files each hour into exactly one bucket, with the evening wrapping past midnight', () => {
    expect(timeOfDayBucket(at(7))).toBe('morning');
    expect(timeOfDayBucket(at(13))).toBe('afternoon');
    expect(timeOfDayBucket(at(21))).toBe('evening');
    expect(timeOfDayBucket(at(1))).toBe('evening');
  });

  it('indexes weekdays Monday-first', () => {
    expect(weekdayIndex({ year: 2026, month: 8, day: 24 })).toBe(0); // a Monday
    expect(weekdayIndex({ year: 2026, month: 8, day: 30 })).toBe(6); // the Sunday after
  });
});

describe('hourly blocks (CH-5)', () => {
  it('has twelve 2-hour blocks that tile the day exactly once', () => {
    expect(HOUR_BLOCKS).toHaveLength(12);
    expect(HOUR_BLOCKS[0]).toMatchObject({ key: '00', label: '00:00–02:00', startHour: 0 });
    expect(HOUR_BLOCKS[9]).toMatchObject({ key: '18', label: '18:00–20:00', startHour: 18 });
    expect(HOUR_BLOCKS[11]).toMatchObject({ key: '22', label: '22:00–00:00', startHour: 22 });
  });

  it('files an hour into the block it falls inside', () => {
    expect(hourBlockKey(at(0))).toBe('00');
    expect(hourBlockKey(at(1))).toBe('00');
    expect(hourBlockKey(at(13))).toBe('12');
    expect(hourBlockKey(at(22))).toBe('22');
    expect(hourBlockKey(at(23))).toBe('22');
  });

  it('is boundary-exclusive at the top of a block', () => {
    // 19:xx is still the 18:00-20:00 block; 20:xx is the next one.
    expect(hourBlockKey(at(19))).toBe('18');
    expect(hourBlockKey(at(20))).toBe('20');
  });

  it('never produces a key outside HOUR_BLOCKS', () => {
    const keys = new Set(HOUR_BLOCKS.map((block) => block.key));
    for (let hour = 0; hour < 24; hour += 1) {
      expect(keys.has(hourBlockKey(at(hour)))).toBe(true);
    }
  });
});

describe('trajectory signal (I6-05)', () => {
  it('uses intensity when the user set one', () => {
    expect(trajectorySignal({ valence: 'negative', intensity: 4 })).toBeCloseTo(-0.8);
  });

  it('falls back to discrete valence when they did not — never a blend of the two scales', () => {
    expect(trajectorySignal({ valence: 'negative', intensity: null })).toBe(-1);
    expect(trajectorySignal({ valence: 'positive', intensity: null })).toBe(1);
  });

  it('keeps a neutral feeling at zero however strongly it was felt', () => {
    expect(trajectorySignal({ valence: 'neutral', intensity: 5 })).toBe(0);
  });

  it('contributes nothing at all for an entry with no feeling — not recorded is not neutral', () => {
    expect(trajectorySignal({ valence: null, intensity: 3 })).toBeNull();
  });
});

describe('passive context factors (#21)', () => {
  it('calls only Saturday and Sunday a weekend', () => {
    expect(dayTypeFor({ year: 2026, month: 8, day: 24 })).toBe('weekday'); // Monday
    expect(dayTypeFor({ year: 2026, month: 8, day: 28 })).toBe('weekday'); // Friday
    expect(dayTypeFor({ year: 2026, month: 8, day: 29 })).toBe('weekend'); // Saturday
    expect(dayTypeFor({ year: 2026, month: 8, day: 30 })).toBe('weekend'); // Sunday
  });

  it('files every month into exactly one meteorological season', () => {
    expect(seasonFor({ year: 2026, month: 1, day: 15 })).toBe('winter');
    expect(seasonFor({ year: 2026, month: 4, day: 15 })).toBe('spring');
    expect(seasonFor({ year: 2026, month: 7, day: 15 })).toBe('summer');
    expect(seasonFor({ year: 2026, month: 10, day: 15 })).toBe('autumn');
    expect(seasonFor({ year: 2026, month: 12, day: 15 })).toBe('winter');
  });

  it('derives exactly one key per category, from the date and time alone', () => {
    const factors = contextFactorsForEntry({ year: 2026, month: 8, day: 30 }, at(21));
    expect(factors).toEqual([
      'weekday:sunday',
      'daytype:weekend',
      'timeofday:evening',
      'season:summer',
    ]);
  });

  it('never derives a second key in the same category for one entry', () => {
    const categories = (factor: string) => factor.split(':')[0];
    for (const [entryDate, createdAt] of [
      [{ year: 2026, month: 1, day: 5 }, at(6)],
      [{ year: 2026, month: 8, day: 24 }, at(13)],
      [{ year: 2026, month: 12, day: 31 }, at(0)],
    ] as const) {
      const factors = contextFactorsForEntry(entryDate, createdAt);
      expect(new Set(factors.map(categories)).size).toBe(factors.length);
    }
  });

  it('reads like the topic sentence, with the context phrase in place of "mentioning X"', () => {
    const text = contextNarrative('anxious', 'on Sundays', associationFrom(8, 12, 3, 28));
    expect(text).toBe(
      'You felt anxious in 8 of 12 entries on Sundays in the last 30 days (67%), ' +
        'and in 3 of 28 other entries (11%).',
    );
    expect(text).not.toMatch(/\brecent\b/i);
  });

  it('says so plainly when the comparison could not be made, same as the topic card', () => {
    expect(contextNarrative('anxious', 'on Sundays', associationFrom(4, 4, 0, 0))).toContain(
      'There are not enough other entries to compare.',
    );
  });

  it('states plainly when the window holds nothing for this factor at all', () => {
    expect(contextNarrative('anxious', 'on Sundays', associationFrom(0, 0, 4, 20))).toBe(
      'You have no entries on Sundays in the last 30 days.',
    );
  });
});

describe('"Worth trying" recommendation sentences (R-1)', () => {
  it('states the protective case: an inverse pattern, negative feeling', () => {
    // The badge that made this pattern qualify already reads 'keep' — see `badgeDirectionFor`
    // (inverse + negative). This is exactly the issue's own worked example, minus the markdown
    // bolding the issue's prose used only for emphasis in the ticket, never as literal copy.
    const text = recommendationSentenceFor('inverse', 'anxious', 'exercise', 2.6667, 4, 6, 1, 4);
    expect(text).toBe(
      'On days without exercise, anxious is 2.7× more likely (4 of 6 without vs 1 of 4 with). ' +
        "More exercise days may help — here's the evidence.",
    );
    // Task 3: association, never causation, and never imperative medical-ish advice.
    expect(text).not.toMatch(/will fix|cure|prevent|guarantee|protects|causes|because/i);
  });

  it('states the symmetric case: a forward pattern, positive feeling — "keep doing"', () => {
    const text = recommendationSentenceFor('forward', 'calm', 'reading', 4.5, 3, 4, 1, 6);
    expect(text).toBe(
      'On days with reading, calm is 4.5× more likely (3 of 4 with vs 1 of 6 without). ' +
        "Keep doing reading — here's the evidence.",
    );
    expect(text).not.toMatch(/will fix|cure|prevent|guarantee|protects|causes|because/i);
  });

  it('rounds the lift to one decimal — the same precision the pattern card badge itself uses', () => {
    expect(recommendationSentenceFor('inverse', 'sad', 'walking', 3, 5, 10, 1, 6)).toContain(
      '3.0× more likely (5 of 10 without vs 1 of 6 with)',
    );
  });

  it('gives each kind its own headline — not re-derivable from `action_topic` alone', () => {
    expect(recommendationHeadlineFor('inverse', 'exercise')).toBe('More exercise days');
    expect(recommendationHeadlineFor('forward', 'reading')).toBe('Keep doing reading');
  });
});

describe('mixed-valence pairing (E-1b, #26)', () => {
  const valenceOf = (key: string): string | undefined =>
    ({ happy: 'positive', disappointed: 'negative', calm: 'neutral' })[key];

  it('is mixed only when a positive and a negative feeling both appear', () => {
    expect(isMixedValence(['happy', 'disappointed'], valenceOf)).toBe(true);
    expect(isMixedValence(['happy'], valenceOf)).toBe(false);
    expect(isMixedValence(['disappointed'], valenceOf)).toBe(false);
    expect(isMixedValence(['happy', 'calm'], valenceOf)).toBe(false);
    expect(isMixedValence(['disappointed', 'calm'], valenceOf)).toBe(false);
    expect(isMixedValence(['calm', 'calm'], valenceOf)).toBe(false);
    expect(isMixedValence([], valenceOf)).toBe(false);
  });

  it('skips a feeling key it has no valence for, rather than guessing', () => {
    expect(isMixedValence(['happy', 'unknown-key'], valenceOf)).toBe(false);
  });

  describe('isPairExcluded (#37, L-2): the predicate extracted for reuse by ProgressService', () => {
    it('never excludes a single-valence entry, whatever confirmedPairs holds', () => {
      expect(isPairExcluded(false, new Set(), 'topic-a', 'happy')).toBe(false);
      expect(isPairExcluded(false, new Set(['topic-a happy']), 'topic-a', 'sad')).toBe(false);
    });

    it('excludes a mixed-valence entry from a pair it never confirmed', () => {
      expect(isPairExcluded(true, new Set(), 'topic-a', 'happy')).toBe(true);
      expect(isPairExcluded(true, new Set(['topic-b happy']), 'topic-a', 'happy')).toBe(true);
    });

    it('does not exclude a mixed-valence entry from the exact pair it confirmed', () => {
      expect(isPairExcluded(true, new Set(['topic-a happy']), 'topic-a', 'happy')).toBe(false);
    });
  });
});
