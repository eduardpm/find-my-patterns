/**
 * T034 / T036 — ports of `backend/tests/unit/test_pattern_detection.py` and the topic-extraction
 * behaviour, exercising the parts that are pure functions with no database and no LLM.
 *
 * These are the rules constitution Principle III requires to be deterministic and independently
 * testable.
 */

import { describe, expect, it } from 'vitest';
import {
  directionForValence,
  MIN_OCCURRENCE_THRESHOLD,
  qualifyingPairs,
} from '../../src/insights/patterns.service';
import { findCuratedMatches } from '../../src/topics/topics.service';

const pair = (topic: string, feeling: string): [string, string] => [topic, feeling];

describe('qualifyingPairs — the minimum-occurrence rule (FR-008)', () => {
  it('uses a threshold of three', () => {
    expect(MIN_OCCURRENCE_THRESHOLD).toBe(3);
  });

  it('surfaces a pair that reaches the threshold', () => {
    const result = qualifyingPairs([
      pair('t1', 'sleepy'),
      pair('t1', 'sleepy'),
      pair('t1', 'sleepy'),
    ]);
    expect(result.get('t1 sleepy')).toBe(3);
  });

  it('withholds a pair one occurrence short', () => {
    const result = qualifyingPairs([pair('t1', 'sleepy'), pair('t1', 'sleepy')]);
    expect(result.size).toBe(0);
  });

  it('counts each topic-feeling pair separately', () => {
    const result = qualifyingPairs([
      pair('t1', 'sleepy'),
      pair('t1', 'sleepy'),
      pair('t1', 'happy'),
      pair('t1', 'happy'),
      pair('t1', 'happy'),
    ]);
    expect(result.has('t1 sleepy')).toBe(false);
    expect(result.get('t1 happy')).toBe(3);
  });

  it('returns the actual count, not just membership', () => {
    const result = qualifyingPairs(Array.from({ length: 7 }, () => pair('t1', 'sad')));
    expect(result.get('t1 sad')).toBe(7);
  });

  it('handles an empty input', () => {
    expect(qualifyingPairs([]).size).toBe(0);
  });

  it('respects an explicit threshold', () => {
    expect(qualifyingPairs([pair('t1', 'sad'), pair('t1', 'sad')], 2).get('t1 sad')).toBe(2);
  });
});

describe('directionForValence (FR-011)', () => {
  it('suggests keeping a positive habit', () => {
    expect(directionForValence('positive')).toBe('keep');
  });

  it('suggests changing a negative one', () => {
    expect(directionForValence('negative')).toBe('change');
  });

  it('groups neutral with change — there is no positive signal to reinforce', () => {
    expect(directionForValence('neutral')).toBe('change');
  });
});

describe('topic extraction', () => {
  it('matches the classic spec example', () => {
    expect(findCuratedMatches('drank a coca cola and felt sleepy')).toContain('coca cola');
  });

  it('folds surface variants onto one canonical topic', () => {
    for (const text of ['had a coke', 'coca-cola please', 'some cola']) {
      expect(findCuratedMatches(text)).toContain('coca cola');
    }
  });

  it('can find several topics in one entry', () => {
    const matches = findCuratedMatches('pizza and beer after the gym');
    expect(matches).toContain('junk food');
    expect(matches).toContain('alcohol');
    expect(matches).toContain('exercise');
  });

  it.each([
    ['I barely slept and skipped breakfast', ['sleep', 'skipped meal']],
    ['I was alone in the park all afternoon', ['time alone', 'outdoors']],
    ['A headache started after my medication', ['headache', 'medication']],
    ['The crowded commute was extremely noisy', ['crowds', 'commute', 'noise']],
    ['Meditation and deep breathing helped', ['meditation']],
    ['I had coffee and scrolled social media', ['coffee', 'screen time']],
    ['I argued with my partner', ['conflict', 'partner']],
    ['Rainy weather and no walk today', ['rainy weather']],
  ])('extracts richer daily context from %j', (text, expected) => {
    const matches = findCuratedMatches(text);
    for (const topic of expected) expect(matches).toContain(topic);
  });

  it('finds nothing in text that mentions no tracked topic', () => {
    expect(findCuratedMatches('a quiet morning by the window').size).toBe(0);
  });

  // -------------------------------------------------------------------------------------------
  // A mention is a whole word, not a substring.
  //
  // Spec 002 FR-009 asks for correlations with topics "mentioned in entry content". The original
  // implementation used raw substring containment, so "ran" matched inside "drank" and "grandma"
  // and recorded the topic `exercise` for someone who had only had a drink. These assertions pin
  // the spec-correct behaviour.
  // -------------------------------------------------------------------------------------------

  it('does not match "ran" inside "drank"', () => {
    const matches = findCuratedMatches('i drank water');
    expect(matches.has('exercise')).toBe(false);
  });

  it('does not match "ran" inside "grandma"', () => {
    expect(findCuratedMatches('grandma called today').has('exercise')).toBe(false);
  });

  it('still matches "ran" when it is actually the word', () => {
    expect(findCuratedMatches('i ran five miles')).toContain('exercise');
  });

  it('records only what was really mentioned', () => {
    const matches = findCuratedMatches('drank a coca cola and felt sluggish');
    expect(matches).toContain('coca cola');
    expect(matches.has('exercise')).toBe(false);
  });

  it('matches multi-word and hyphenated variants as phrases', () => {
    expect(findCuratedMatches('ordered some fast food')).toContain('takeout');
    expect(findCuratedMatches('a cold coca-cola')).toContain('coca cola');
    expect(findCuratedMatches('i worked out this morning')).toContain('exercise');
  });

  it('does not match a topic word buried inside a longer word', () => {
    // "tea" inside "steamed", "work" inside "network", "nap" inside "kidnapped".
    expect(findCuratedMatches('steamed vegetables').has('tea')).toBe(false);
    expect(findCuratedMatches('the network was down').has('work')).toBe(false);
    expect(findCuratedMatches('watched a film about someone kidnapped').has('sleep')).toBe(false);
  });
});
