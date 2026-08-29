/**
 * The vocabulary itself, and the deterministic half of reading the analyser's answer.
 *
 * `reconcileFeelings` is Principle III's boundary in this feature: the model proposes, and this
 * function alone decides what the entry is actually tagged with. It is pure, so it is tested
 * directly rather than through a live model.
 */

import { describe, expect, it } from 'vitest';
import {
  FEELING_GROUP_SEED,
  FEELING_KEYS,
  FEELING_SEED,
  GROUP_BY_FEELING_KEY,
  MAX_FEELINGS_PER_ENTRY,
} from '../../src/db/feeling-vocabulary';
import { reconcileFeelings } from '../../src/inference/worker';

describe('the feeling vocabulary', () => {
  it('keeps every key the original eight-feeling diary used', () => {
    // These are foreign keys in real diaries. Renaming one orphans an entry.
    for (const key of [
      'happy',
      'excited',
      'neutral',
      'sleepy',
      'exhausted',
      'stressed',
      'sad',
      'depressed',
    ]) {
      expect(FEELING_KEYS).toContain(key);
    }
  });

  it('has no duplicate keys and puts every feeling in a real group', () => {
    expect(new Set(FEELING_KEYS).size).toBe(FEELING_KEYS.length);
    const groups = new Set(FEELING_GROUP_SEED.map((group) => group.key));
    for (const feeling of FEELING_SEED) expect(groups.has(feeling.groupKey)).toBe(true);
  });

  it('gives each group its own valence, inherited by every feeling except a stated override', () => {
    // #60: `calm`, `content`, `relaxed`, `focused` and `curious` are pleasant states that sit in
    // "Steady" for presentation only — their valence is `positive`, not the group's `neutral`.
    // Grouping and labels are unaffected; this is the one sanctioned place a feeling's valence is
    // allowed to diverge from its group's, and the test pins the divergence to exactly these five
    // so a future change cannot introduce another one silently.
    const OVERRIDDEN: Record<string, string> = {
      calm: 'positive',
      content: 'positive',
      relaxed: 'positive',
      focused: 'positive',
      curious: 'positive',
    };
    for (const group of FEELING_GROUP_SEED) {
      const members = FEELING_SEED.filter((feeling) => feeling.groupKey === group.key);
      expect(members.length).toBeGreaterThanOrEqual(3);
      for (const member of members) {
        expect(member.valence).toBe(OVERRIDDEN[member.key] ?? group.valence);
      }
    }
  });

  it('orders feelings so no two share a sort position', () => {
    const orders = FEELING_SEED.map((feeling) => feeling.sortOrder);
    expect(new Set(orders).size).toBe(orders.length);
  });
});

describe('reconcileFeelings', () => {
  it('keeps a well-formed proposal, strongest first', () => {
    expect(
      reconcileFeelings([
        { group_key: 'low', feeling_key: 'exhausted', confidence: 0.4 },
        { group_key: 'tense', feeling_key: 'stressed', confidence: 0.9 },
      ]),
    ).toEqual([
      { key: 'stressed', confidence: 0.9 },
      { key: 'exhausted', confidence: 0.4 },
    ]);
  });

  it('keeps the feeling and discards the group when the two disagree', () => {
    // `happy` is in `uplifted`, not `low`. The specific word is the more informative half.
    const [only] = reconcileFeelings([{ group_key: 'low', feeling_key: 'happy', confidence: 0.8 }]);
    expect(only.key).toBe('happy');
    expect(GROUP_BY_FEELING_KEY.happy).toBe('uplifted');
  });

  it('discounts a mismatched pair rather than trusting it fully', () => {
    const [mismatched] = reconcileFeelings([
      { group_key: 'low', feeling_key: 'happy', confidence: 0.8 },
    ]);
    expect(mismatched.confidence).toBe(0.4);
  });

  it('collapses a repeated feeling to its highest confidence', () => {
    expect(
      reconcileFeelings([
        { group_key: 'uplifted', feeling_key: 'proud', confidence: 0.3 },
        { group_key: 'uplifted', feeling_key: 'proud', confidence: 0.7 },
      ]),
    ).toEqual([{ key: 'proud', confidence: 0.7 }]);
  });

  it('never returns more feelings than an entry may carry', () => {
    const flood = FEELING_SEED.map((feeling) => ({
      group_key: feeling.groupKey,
      feeling_key: feeling.key,
      confidence: 0.5,
    }));
    expect(reconcileFeelings(flood)).toHaveLength(MAX_FEELINGS_PER_ENTRY);
  });

  it('breaks a confidence tie deterministically, so two runs agree', () => {
    const tied = [
      { group_key: 'steady', feeling_key: 'calm', confidence: 0.5 },
      { group_key: 'steady', feeling_key: 'content', confidence: 0.5 },
    ];
    expect(reconcileFeelings(tied).map((f) => f.key)).toEqual(['calm', 'content']);
    expect(reconcileFeelings([...tied].reverse()).map((f) => f.key)).toEqual(['calm', 'content']);
  });

  it('returns nothing when the model proposed nothing', () => {
    expect(reconcileFeelings([])).toEqual([]);
  });
});
