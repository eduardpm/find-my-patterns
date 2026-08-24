import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { decodeJson, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';

/**
 * Deterministic, keyword-based topic extraction (constitution Principle III: no LLM here).
 *
 * Matching is on **whole words and phrases**, not raw substrings. Spec 002 FR-009 asks for
 * correlations between topics "mentioned in entry content", and a substring match is not a mention:
 * the previous implementation matched `"ran"` inside `"drank"` and `"grandma"`, so *"I drank water"*
 * recorded the topic **exercise** and fed it into pattern detection. That was a defect against the
 * spec, and the spec governs — an earlier implementation's behaviour is not the authority.
 *
 * Deliberately still simple: word-boundary containment against a curated list, no stemming, no NLP.
 * Good enough to catch recurring nouns, which is all the pattern engine needs.
 */

export const CURATED_TOPIC_KEYWORDS: Record<string, string[]> = {
  // Food, drink, and substances
  'coca cola': ['coca cola', 'coca-cola', 'coke', 'cola'],
  coffee: ['coffee', 'espresso', 'latte', 'cappuccino'],
  tea: ['tea'],
  'energy drinks': ['energy drink', 'energy drinks', 'red bull', 'monster energy'],
  hydration: ['water', 'hydration', 'hydrated', 'dehydrated'],
  alcohol: ['beer', 'wine', 'alcohol', 'cocktail'],
  smoking: ['smoke', 'smoked', 'smoking', 'cigarette', 'cigarettes', 'vape', 'vaping'],
  takeout: ['takeout', 'take-out', 'take out', 'fast food', 'delivery'],
  'junk food': ['pizza', 'chips', 'candy', 'chocolate', 'fries', 'junk food'],
  sugar: ['sugar', 'sugary', 'sweets', 'dessert', 'cake', 'cookies', 'ice cream'],
  'fruit and vegetables': ['fruit', 'fruits', 'vegetable', 'vegetables', 'salad'],
  'skipped meal': [
    'skipped breakfast',
    'skipped lunch',
    'skipped dinner',
    'skipped a meal',
    'empty stomach',
    'fasting',
  ],

  // Movement, routine, and restorative activities
  exercise: ['exercise', 'gym', 'workout', 'worked out', 'ran', 'running', 'yoga'],
  walking: ['walk', 'walked', 'walking', 'hike', 'hiked', 'hiking'],
  cycling: ['cycle', 'cycled', 'cycling', 'bike ride', 'biked', 'biking'],
  sedentary: ['sedentary', 'sitting all day', 'sat all day'],
  sleep: ['slept', 'sleep', 'nap', 'napped', 'insomnia', 'bedtime', 'woke up', 'poor sleep'],
  rest: ['rested', 'resting', 'downtime', 'took a break'],
  commute: ['commute', 'commuting', 'traffic', 'train ride', 'bus ride'],
  chores: ['chores', 'cleaned', 'cleaning', 'laundry', 'housework'],

  // Work and social setting. Keep specific relationships separate: "family" and "partner" can
  // have very different within-person associations even though both are broadly social time.
  work: ['work', 'meeting', 'deadline', 'overtime', 'boss'],
  study: ['school', 'class', 'studied', 'studying', 'homework', 'exam'],
  friends: ['friend', 'friends', 'hangout', 'hung out'],
  family: ['family', 'parent', 'parents', 'mother', 'father', 'sibling', 'siblings'],
  partner: ['partner', 'boyfriend', 'girlfriend', 'husband', 'wife', 'spouse'],
  colleagues: ['colleague', 'colleagues', 'coworker', 'coworkers', 'team-mate', 'teammate'],
  'time alone': ['alone', 'by myself', 'on my own', 'solitude'],
  'social event': ['party', 'social event', 'gathering', 'get-together'],
  conflict: ['argument', 'argued', 'fight', 'fought', 'conflict', 'disagreement'],

  // Body and health context
  hunger: ['hungry', 'hunger', 'starving'],
  pain: ['pain', 'painful', 'aching', 'sore'],
  headache: ['headache', 'headaches', 'migraine', 'migraines'],
  digestion: ['bloated', 'bloating', 'nausea', 'nauseous', 'indigestion', 'stomach ache'],
  illness: ['sick', 'ill', 'fever', 'have a cold', 'caught a cold', 'flu'],
  medication: ['medication', 'medicine', 'meds', 'prescription', 'painkiller'],
  'menstrual cycle': [
    'my period',
    'on my period',
    'got my period',
    'menstruation',
    'menstrual',
    'pms',
    'ovulation',
  ],

  // Environment, attention, and coping
  'screen time': ['phone', 'scrolling', 'social media', 'screen time'],
  outdoors: ['outside', 'outdoors', 'park', 'nature', 'forest', 'garden'],
  'sunny weather': ['sunny', 'sunshine', 'clear skies'],
  'rainy weather': ['rain', 'raining', 'rainy', 'storm', 'stormy'],
  'hot weather': ['heatwave', 'hot weather', 'too hot'],
  'cold weather': ['cold weather', 'freezing outside', 'too cold'],
  noise: ['noise', 'noisy', 'loud'],
  crowds: ['crowd', 'crowds', 'crowded'],
  travel: ['travel', 'travelled', 'traveled', 'trip', 'vacation', 'holiday'],
  music: ['music', 'playlist', 'concert', 'sang', 'singing'],
  reading: ['read a book', 'reading', 'book'],
  meditation: ['meditated', 'meditation', 'mindfulness', 'breathing exercise', 'deep breathing'],
  therapy: ['therapy', 'therapist', 'counselling', 'counseling'],
};

interface TopicRow {
  id: string;
  name: string;
  aliases: string;
  first_seen_at: string;
  last_seen_at: string;
}

export interface Topic {
  id: string;
  name: string;
}

const escapeRegex = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Does `text` mention `phrase` as a whole word or phrase?
 *
 * `\b` at each end is what separates a mention from a coincidence: "ran" matches *"I ran home"* but
 * not *"I drank water"*. Multi-word variants ("coca cola", "worked out") and hyphenated ones
 * ("coca-cola") work unchanged, since the boundaries only apply at the ends.
 */
export function mentions(text: string, phrase: string): boolean {
  return new RegExp(`\\b${escapeRegex(phrase)}\\b`, 'i').test(text);
}

/** Pure, DB-free: which curated topics does this text actually mention? */
export function findCuratedMatches(textLower: string): Set<string> {
  const matches = new Set<string>();
  for (const [canonical, variants] of Object.entries(CURATED_TOPIC_KEYWORDS)) {
    if (variants.some((variant) => mentions(textLower, variant))) matches.add(canonical);
  }
  return matches;
}

@Injectable()
export class TopicsService {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  private findExistingTopicMatches(textLower: string): Set<string> {
    const matches = new Set<string>();
    const rows = this.db.prepare('SELECT * FROM topics').all() as TopicRow[];
    for (const row of rows) {
      const names = [row.name, ...decodeJson<string[]>(row.aliases ?? '[]')];
      if (names.some((name) => name && mentions(textLower, name.toLowerCase()))) {
        matches.add(row.name);
      }
    }
    return matches;
  }

  private getOrCreateTopic(name: string): Topic {
    const existing = this.db.prepare('SELECT * FROM topics WHERE name = ?').get(name) as
      TopicRow | undefined;
    const now = encodeDateTime(nowUtc());

    if (existing) {
      this.db.prepare('UPDATE topics SET last_seen_at = ? WHERE id = ?').run(now, existing.id);
      return { id: existing.id, name: existing.name };
    }

    const id = randomUUID();
    this.db
      .prepare(
        'INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?)',
      )
      .run(id, name, encodeJson([]), now, now);
    return { id, name };
  }

  /**
   * Find-or-create the topics mentioned in an entry and link them to it.
   *
   * Idempotent: pattern recomputation re-scans every eligible entry on each run, so this must never
   * duplicate a link or a topic row.
   */
  extractAndLinkTopics(entryId: string, rawText: string): Topic[] {
    const textLower = (rawText ?? '').toLowerCase();
    if (!textLower.trim()) return [];

    const candidates = new Set([
      ...findCuratedMatches(textLower),
      ...this.findExistingTopicMatches(textLower),
    ]);
    if (candidates.size === 0) return [];

    const alreadyLinked = new Set(
      (
        this.db.prepare('SELECT topic_id FROM entry_topics WHERE entry_id = ?').all(entryId) as {
          topic_id: string;
        }[]
      ).map((r) => r.topic_id),
    );

    const linked: Topic[] = [];
    for (const name of candidates) {
      const topic = this.getOrCreateTopic(name);
      linked.push(topic);
      if (!alreadyLinked.has(topic.id)) {
        // `extracted_by` records how the link was found. Every link this service makes is
        // keyword-based; the column is nullable but is never written as NULL.
        this.db
          .prepare('INSERT INTO entry_topics (entry_id, topic_id, extracted_by) VALUES (?, ?, ?)')
          .run(entryId, topic.id, 'keyword');
      }
    }
    return linked;
  }

  topicsForEntry(entryId: string): Topic[] {
    return this.db
      .prepare(
        'SELECT t.id, t.name FROM topics t JOIN entry_topics et ON et.topic_id = t.id WHERE et.entry_id = ?',
      )
      .all(entryId) as Topic[];
  }
}
