/**
 * The Daylio mood → feeling mapping (L-1b, #35): conservative by construction — every key is
 * checked against `FeelingKey` at compile time, and anything not one of the five defaults must
 * come back `null` so the importer skips and reports it rather than guessing.
 */

import { describe, expect, it } from 'vitest';
import { FEELING_KEYS } from '../../src/db/feeling-vocabulary';
import {
  DAYLIO_MOOD_MAP,
  mapDaylioMood,
  normalizeDaylioMood,
} from '../../src/import/daylio-mood-map';

describe('DAYLIO_MOOD_MAP', () => {
  it("maps exactly Daylio's five default moods", () => {
    expect(Object.keys(DAYLIO_MOOD_MAP).sort()).toEqual(['awful', 'bad', 'good', 'meh', 'rad']);
  });

  it('maps every value onto a feeling this vocabulary actually has', () => {
    for (const feelingKey of Object.values(DAYLIO_MOOD_MAP)) {
      expect(FEELING_KEYS as readonly string[]).toContain(feelingKey);
    }
  });

  it('matches the mapping proposed in the PR', () => {
    expect(DAYLIO_MOOD_MAP).toEqual({
      rad: 'happy',
      good: 'content',
      meh: 'neutral',
      bad: 'sad',
      awful: 'depressed',
    });
  });
});

describe('normalizeDaylioMood', () => {
  it('trims and lowercases', () => {
    expect(normalizeDaylioMood('  Rad ')).toBe('rad');
  });

  it("handles the trailing space Daylio's own sample export writes", () => {
    expect(normalizeDaylioMood('sad ')).toBe('sad');
  });
});

describe('mapDaylioMood', () => {
  it('maps each default mood case- and whitespace-insensitively', () => {
    expect(mapDaylioMood('rad')).toBe('happy');
    expect(mapDaylioMood(' Good ')).toBe('content');
    expect(mapDaylioMood('MEH')).toBe('neutral');
    expect(mapDaylioMood('bad')).toBe('sad');
    expect(mapDaylioMood('Awful')).toBe('depressed');
  });

  it('never guesses at a custom or renamed mood — null, not a nearest match', () => {
    expect(mapDaylioMood('fantastic')).toBeNull();
    expect(mapDaylioMood('average')).toBeNull();
    expect(mapDaylioMood('')).toBeNull();
  });
});
