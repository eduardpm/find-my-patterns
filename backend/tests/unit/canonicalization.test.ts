/**
 * Topic normalisation and canonical resolution (roadmap A4).
 *
 * The audit's finding was that LLM-proposed topics are one-shot and unmerged, so "project review",
 * "project meeting" and "review" are three rows and none of them ever reaches three occurrences.
 * These are the rules that fix it — and, just as importantly, the rules that stop the fix from
 * merging things that are genuinely different.
 */

import { describe, expect, it } from 'vitest';
import {
  canonicalTopicName,
  curatedTopicFor,
  normalizeTopicName,
  significantStems,
  stemToken,
} from '../../src/topics/canonicalization';

const known = (...names: string[]) => names.map((name) => ({ name, aliases: [] as string[] }));

describe('normalizeTopicName (A4-01)', () => {
  it('lowercases, trims, strips punctuation and collapses whitespace', () => {
    expect(normalizeTopicName('  Project   Review. ')).toBe('project review');
    expect(normalizeTopicName('Coca-Cola')).toBe('coca cola');
  });

  it('leaves nothing behind for a proposal that was only punctuation', () => {
    expect(normalizeTopicName('!!!')).toBe('');
  });
});

describe('stemming', () => {
  it('brings a word and its inflections to the same stem', () => {
    // The property that matters is convergence, not what the stem happens to spell.
    expect(stemToken('meetings')).toBe(stemToken('meeting'));
    expect(stemToken('walked')).toBe(stemToken('walking'));
    expect(stemToken('classes')).toBe(stemToken('class'));
    expect(stemToken('vegetables')).toBe(stemToken('vegetable'));
    expect(stemToken('worries')).toBe('worry');
  });

  it('leaves short and already-singular words alone', () => {
    // The bug the whole topic extractor was fixed for, in a different disguise: an over-eager
    // stemmer merges topics the diary kept apart.
    expect(stemToken('rest')).toBe('rest');
    expect(stemToken('tea')).toBe('tea');
    expect(stemToken('stress')).toBe('stress');
    expect(stemToken('focus')).toBe('focus');
  });

  it('drops connectives that carry no topic meaning', () => {
    expect(significantStems('fruit and vegetables')).toEqual(['fruit', 'vegetable']);
  });
});

describe('curatedTopicFor', () => {
  it('answers with the curated topic a phrase belongs to', () => {
    expect(curatedTopicFor('gym session')).toBe('exercise');
    expect(curatedTopicFor('project review')).toBe('work');
  });

  it('breaks a two-way match on the longest matched variant, never on key order', () => {
    // "coca cola" is a longer, more specific variant than "coffee"'s.
    expect(curatedTopicFor('coca cola and coffee')).toBe('coca cola');
  });

  it('says nothing about a phrase the list does not cover', () => {
    expect(curatedTopicFor('kintsugi bowl')).toBeNull();
  });
});

describe('canonicalTopicName (A4-02)', () => {
  it('folds the fragments the audit found onto one canonical topic — A4-SC1', () => {
    const resolved = ['project review', 'project meeting', 'review'].map((proposal) =>
      canonicalTopicName(proposal, []),
    );
    expect(resolved).toEqual(['work', 'work', 'work']);
  });

  it('matches an existing topic through an alias, with no model involved — A4-SC3', () => {
    const topics = [{ name: 'kintsugi', aliases: ['gold repair'] }];
    expect(canonicalTopicName('Gold Repair.', topics)).toBe('kintsugi');
  });

  it('treats the same words with different endings as the same topic', () => {
    expect(canonicalTopicName('kintsugi bowls', known('kintsugi bowl'))).toBe('kintsugi bowl');
  });

  it('keeps the shorter phrase when one topic is contained in another', () => {
    expect(canonicalTopicName('large kintsugi bowl', known('kintsugi bowl'))).toBe('kintsugi bowl');
  });

  it('stores a genuinely novel topic under its own name rather than dropping it — A4-10', () => {
    expect(canonicalTopicName('kintsugi', known('obsidian shard'))).toBe('kintsugi');
  });

  it('leaves two phrases apart when neither contains the other', () => {
    // They share the word "bowl" and nothing else. Merging on a single shared word is how
    // "morning coffee" and "morning walk" would both become "morning".
    // Stored under its own normalised name — stopwords and all, because the name is what the user
    // will read on the card, not the stem list the matching used.
    expect(canonicalTopicName('a bowl of soup', known('kintsugi bowl'))).toBe('a bowl of soup');
  });

  it('has nothing to say about an empty proposal', () => {
    expect(canonicalTopicName('   ', known('kintsugi'))).toBeNull();
  });
});
