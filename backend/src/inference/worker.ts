import { randomUUID } from 'node:crypto';
import * as fs from 'node:fs';
import { z } from 'zod';
import { loadConfig } from '../config';
import { assertCompatible } from '../db/compatibility';
import { decodeJson, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { openDiary, type DiaryDatabase } from '../db/database';
import { createScopedDb } from '../db/scoped-db';
import { canonicalTopicName, normalizeTopicName } from '../topics/canonicalization';
import { CURATED_TOPIC_KEYWORDS } from '../topics/topics.service';
import { templateSuggestionFor } from '../insights/patterns.service';
import {
  MAX_NARRATION_ATTEMPTS,
  NARRATION_BACKOFF_BASE_MS,
  NARRATION_BACKOFF_MAX_MS,
  NARRATION_MIN_INTERVAL_MS,
} from '../insights/constants';
import {
  FEELING_GROUP_SEED,
  FEELING_GROUP_KEYS,
  FEELING_KEYS,
  FEELING_SEED,
  GROUP_BY_FEELING_KEY,
  MAX_FEELINGS_PER_ENTRY,
} from '../db/feeling-vocabulary';
import { type EntryAnalysis, type ProposedPairing } from './inference';

interface Job {
  id: string;
  /**
   * The job's owner (#135). Read off `inference_jobs.user_id` by the single cross-user
   * `claimNext` query below, and from here on the one thing that decides which user's rows
   * `processJob`/`applyAnalysis`/`recordFailure` are allowed to touch: each of them is handed a
   * `DiaryDatabase` obtained from `ScopedDb.forUser(job.userId)`, never the raw connection.
   */
  userId: string;
  kind: 'entry_analysis' | 'transcript_format';
  entryId: string;
  attempts: number;
  resultJson: string | null;
}

interface OllamaChatResponse {
  message?: { content?: string };
}

/** Group key → its feeling keys, for describing the vocabulary's shape in the prompt. */
const FEELING_SEED_BY_GROUP = new Map<string, string[]>(
  FEELING_GROUP_SEED.map((group) => [
    group.key,
    FEELING_SEED.filter((feeling) => feeling.groupKey === group.key).map((feeling) => feeling.key),
  ]),
);

/**
 * What the analyser is asked for.
 *
 * `group_key` is not redundant with `feeling_key`, and it is not stored: it is a cheap
 * self-check. A small local model that has to name the bucket before the word inside it picks the
 * word far more consistently, and a pair that disagrees is a signal the choice was careless —
 * see `reconcileFeelings`.
 */
const modelOutputSchema = z.object({
  feelings: z
    .array(
      z.object({
        group_key: z.enum(FEELING_GROUP_KEYS),
        feeling_key: z.enum(FEELING_KEYS),
        confidence: z.number().min(0).max(1),
      }),
    )
    .min(1)
    .max(MAX_FEELINGS_PER_ENTRY),
  topics: z.array(z.string()).max(10),
  // E-1a: aspect-based extraction. For each topic the model just proposed above, which of the
  // feelings it *also* just proposed (if any) the text ties that topic to — never a free-standing
  // feeling of its own, which is what `reconcilePairings` enforces regardless of what the model
  // actually returns here. An empty `feeling_keys` list is a normal, common answer: most topics on
  // a single-valence entry have nothing ambiguous to pair.
  topic_feelings: z
    .array(
      z.object({
        topic: z.string(),
        feeling_keys: z.array(z.enum(FEELING_KEYS)).max(MAX_FEELINGS_PER_ENTRY),
      }),
    )
    .max(10),
});

const suggestionSchema = z.object({ suggestion: z.string() });
const SUGGESTION_FORMAT = {
  type: 'object',
  properties: { suggestion: { type: 'string' } },
  required: ['suggestion'],
  additionalProperties: false,
} as const;

const formattedTranscriptSchema = z.object({ formatted_text: z.string() });
const FORMATTED_TRANSCRIPT_FORMAT = {
  type: 'object',
  properties: { formatted_text: { type: 'string' } },
  required: ['formatted_text'],
  additionalProperties: false,
} as const;

const MODEL_FORMAT = {
  type: 'object',
  properties: {
    feelings: {
      type: 'array',
      minItems: 1,
      maxItems: MAX_FEELINGS_PER_ENTRY,
      items: {
        type: 'object',
        properties: {
          group_key: { type: 'string', enum: FEELING_GROUP_KEYS },
          feeling_key: { type: 'string', enum: FEELING_KEYS },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
        },
        required: ['group_key', 'feeling_key', 'confidence'],
        additionalProperties: false,
      },
    },
    topics: {
      type: 'array',
      maxItems: 10,
      items: { type: 'string', minLength: 2, maxLength: 40 },
    },
    topic_feelings: {
      type: 'array',
      maxItems: 10,
      items: {
        type: 'object',
        properties: {
          topic: { type: 'string', minLength: 2, maxLength: 40 },
          feeling_keys: {
            type: 'array',
            maxItems: MAX_FEELINGS_PER_ENTRY,
            items: { type: 'string', enum: FEELING_KEYS },
          },
        },
        required: ['topic', 'feeling_keys'],
        additionalProperties: false,
      },
    },
  },
  required: ['feelings', 'topics', 'topic_feelings'],
  additionalProperties: false,
} as const;

const delay = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

/**
 * Claims the next queued job, across every user's queue in one query (#135).
 *
 * This worker is a single dispatcher, not one poller per user: looping over users here would turn
 * one query per poll into one query per (poll × user count), which is exactly the multiplied load
 * the issue's acceptance criterion 4 forbids, for no benefit — Ollama can only serve one job at a
 * time regardless of whose queue it came from. So the candidate `SELECT` below stays deliberately
 * unscoped, on the raw connection rather than a `ScopedDb` handle: there is no single `userId` a
 * cross-user claim could be scoped to. It now also reads `user_id`, so the `Job` it returns can
 * carry its owner for everything downstream.
 *
 * The claiming `UPDATE`, by contrast, already knows exactly whose row it is about to touch — the
 * `user_id` the `SELECT` just read — so it runs through `ScopedDb.forUser(row.user_id)` and adds
 * `AND user_id = ?` as defence in depth beyond the already-globally-unique primary key. Two queries
 * per poll either way; scoping the second changes what it can touch, not how many round trips it
 * costs.
 */
function claimNext(db: DiaryDatabase): Job | null {
  return db.transaction(() => {
    const row = db
      .prepare(
        `SELECT id, user_id, kind, entry_id, attempts, result_json FROM inference_jobs
         WHERE status = 'queued' AND kind IN ('entry_analysis', 'transcript_format')
         ORDER BY created_at, id LIMIT 1`,
      )
      .get() as
      | {
          id: string;
          user_id: string;
          kind: 'entry_analysis' | 'transcript_format';
          entry_id: string;
          attempts: number;
          result_json: string | null;
        }
      | undefined;
    if (!row) return null;

    const changed = createScopedDb(db)
      .forUser(row.user_id)
      .prepare(
        `UPDATE inference_jobs SET status = 'running', attempts = attempts + 1,
         started_at = ?, error_text = NULL WHERE id = ? AND status = 'queued' AND user_id = ?`,
      )
      .run(encodeDateTime(nowUtc()), row.id, row.user_id);
    if (changed.changes !== 1) return null;
    return {
      id: row.id,
      userId: row.user_id,
      kind: row.kind,
      entryId: row.entry_id,
      attempts: Number(row.attempts) + 1,
      resultJson: row.result_json,
    };
  });
}

/**
 * The model's proposed topics, normalised (A4-01).
 *
 * Only the shape of the string is settled here. *Which* topic a phrase belongs to is decided when
 * the row is written, against the canonical list and the alias table — see `storeAnalysis` — so
 * the model is never the thing that says two phrases mean the same (A4-03).
 */
function normalizeTopics(values: string[]): string[] {
  const ignored = new Set<string>([...FEELING_KEYS, 'feeling', 'feelings', 'mood', 'today']);
  const normalized = values
    .map(normalizeTopicName)
    .filter((value) => value.length >= 2 && value.length <= 40 && !ignored.has(value));
  return [...new Set(normalized)].slice(0, 10);
}

/**
 * Turn what the model returned into the feelings the entry is actually tagged with.
 *
 * Three things happen here, and each is a deterministic rule rather than something the model is
 * trusted with (Principle III):
 *
 *  - **The feeling wins over the group.** The schema already constrains both to the vocabulary, so
 *    a mismatched pair is not a corrupt value — it is a careless one. The specific word carries
 *    more information than the bucket, so the word is kept and the bucket is discarded; the
 *    disagreement only costs the pair some confidence.
 *  - **Duplicates collapse**, keeping the highest confidence seen for that feeling.
 *  - **Strongest first**, so `feelings[0]` — the entry's primary feeling, the one the calendar dot
 *    and the entry rail show — is the model's most confident answer and not merely its first.
 */
export function reconcileFeelings(
  proposed: Array<{ group_key: string; feeling_key: string; confidence: number }>,
): Array<{ key: string; confidence: number }> {
  const byKey = new Map<string, number>();
  for (const item of proposed) {
    const agrees = GROUP_BY_FEELING_KEY[item.feeling_key] === item.group_key;
    const confidence = agrees ? item.confidence : item.confidence / 2;
    const existing = byKey.get(item.feeling_key);
    if (existing === undefined || confidence > existing) byKey.set(item.feeling_key, confidence);
  }
  return [...byKey]
    .map(([key, confidence]) => ({ key, confidence }))
    .sort((a, b) => b.confidence - a.confidence || a.key.localeCompare(b.key))
    .slice(0, MAX_FEELINGS_PER_ENTRY);
}

/**
 * Turn the model's proposed topic↔feeling pairings into something the app is willing to store
 * (E-1a), the same discipline `reconcileFeelings` applies to the feeling list: the model proposes,
 * and every rule that decides what survives is arithmetic on its answer, not trust in it
 * (Principle III).
 *
 *  - **A pairing may only name a topic this analysis actually kept**, compared after the same
 *    normalisation `normalizeTopics` applies — a model that pairs a feeling with a topic it did
 *    not itself propose (or proposed and then got filtered, e.g. too short) has nothing to pair.
 *  - **A pairing may only name a feeling this analysis actually kept**, after `reconcileFeelings`
 *    — aspect-based extraction is "which of the feelings *already found*", never a second,
 *    independent guess at a feeling nothing else corroborates.
 *  - **Topics collapse**, the same way `normalizeTopics` already de-duplicates: two entries for the
 *    same topic union their feeling keys rather than one silently overwriting the other.
 *  - **A topic with nothing left after filtering is simply absent from the result** — "no pairing"
 *    is task 1's explicitly normal, common answer, not an error.
 */
export function reconcilePairings(
  proposed: Array<{ topic: string; feeling_keys: string[] }>,
  topics: string[],
  feelings: Array<{ key: string; confidence: number }>,
): ProposedPairing[] {
  const knownTopics = new Set(topics);
  const knownFeelings = new Set(feelings.map((feeling) => feeling.key));
  const byTopic = new Map<string, Set<string>>();

  for (const item of proposed) {
    const topic = normalizeTopicName(item.topic);
    if (!knownTopics.has(topic)) continue;
    const keys = item.feeling_keys.filter((key) => knownFeelings.has(key));
    if (keys.length === 0) continue;
    const existing = byTopic.get(topic) ?? new Set<string>();
    keys.forEach((key) => existing.add(key));
    byTopic.set(topic, existing);
  }

  return [...byTopic]
    .map(([topic, keys]) => ({ topic, feelingKeys: [...keys].sort() }))
    .sort((a, b) => a.topic.localeCompare(b.topic));
}

async function ollamaAnalysis(text: string): Promise<EntryAnalysis> {
  const config = loadConfig();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90_000);
  const canonicalTopics = Object.keys(CURATED_TOPIC_KEYWORDS).join(', ');
  // Spelled out for the model rather than left to the JSON schema's two flat enums, which say
  // nothing about which feeling lives in which group.
  const groupOverview = FEELING_GROUP_SEED.map(
    (group) => `${group.key} (${FEELING_SEED_BY_GROUP.get(group.key)?.join(', ') ?? ''})`,
  ).join('; ');

  try {
    const response = await fetch(`${config.ollamaUrl}/api/chat`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model: config.ollamaModel,
        stream: false,
        think: false,
        keep_alive: 0,
        format: MODEL_FORMAT,
        // Raised from 400 (originally 220): the response now also carries a topic_feelings entry
        // per topic, and a truncated response is a parse failure, not a shorter answer.
        options: { temperature: 0, num_predict: 600 },
        messages: [
          {
            role: 'system',
            content:
              'Analyze one private diary entry. The feeling vocabulary is organized into ' +
              `groups: ${groupOverview}. For each feeling you report, name its group first, then ` +
              'the specific feeling inside that group, and the feeling must belong to the group ' +
              'you named. Report every distinct feeling the entry genuinely expresses, strongest ' +
              `first, up to ${MAX_FEELINGS_PER_ENTRY}. Report one when the entry expresses one; ` +
              'report several only when the text really carries several — an entry that was hard ' +
              'and then ended well is two feelings, an entry that repeats one mood in different ' +
              'words is still one. Do not pad the list. ' +
              'Extract concrete, reusable factors that could correlate with those feelings: ' +
              'activities, food or drink, sleep, people or social setting, work, health or body ' +
              'state, environment, routines, and coping actions. Do not return emotions as topics. ' +
              `Prefer these canonical topic names when applicable: ${canonicalTopics}. ` +
              'For anything else use a short, lowercase, stable noun phrase. ' +
              'Then, for each topic, decide which of the feelings you reported above (if any) the ' +
              'entry text itself ties that topic to — this is about what the words say, not a ' +
              'guess. A day can be mixed: missing a workout might read as disappointing while a ' +
              'call with family the same day reads as warm, and those are two separate pairings, ' +
              'not one feeling shared across both topics. Leave a topic’s feeling_keys empty ' +
              'when the text does not clearly tie it to a particular feeling — that is the normal, ' +
              'expected answer for a single-mood entry, not something to avoid. Never invent a ' +
              'feeling here that is not already in your feelings list above. Return only the schema.',
          },
          { role: 'user', content: text },
        ],
      }),
    });
    if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}`);
    const body = (await response.json()) as OllamaChatResponse;
    const parsed = modelOutputSchema.parse(JSON.parse(body.message?.content ?? ''));
    const feelings = reconcileFeelings(parsed.feelings);
    const topics = normalizeTopics(parsed.topics);
    return {
      feelings,
      topics,
      pairings: reconcilePairings(parsed.topic_feelings, topics, feelings),
    };
  } finally {
    clearTimeout(timeout);
    // `keep_alive: 0` on the inference request is sufficient in the normal case. This explicit
    // empty-message request is a second guarantee for malformed responses and client-side errors.
    try {
      await fetch(`${config.ollamaUrl}/api/chat`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          model: config.ollamaModel,
          messages: [],
          stream: false,
          keep_alive: 0,
        }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      // The original job error is more useful. Ollama also expires runners independently.
    }
  }
}

/** The longest a suggestion may be. The card shows it in full, so it has to fit on a phone. */
const MAX_SUGGESTION_LENGTH = 180;

/**
 * Decide whether the model's advice is usable, without asking it to mark its own work.
 *
 * The division of labour in an insight is strict: the observation carries the evidence, the
 * suggestion carries the advice. So this rejects anything that reads like the model asserting a
 * fact of its own:
 *
 *  - **No invented evidence.** The one number in an insight is the occurrence count, and it
 *    belongs to the observation, where it was actually measured. "You logged this 5 times" is the
 *    app making up a statistic. This started life as a ban on every digit, which was too blunt in
 *    a way worth recording: the model then wrote "a 10 minute walk", got rejected, and every
 *    insight fell back to the placeholder — a strictly worse product than the risk it avoided.
 *    So the test is a number *making a claim about the diary*, not a number.
 *  - **It has to be about the topic.** A suggestion that never mentions walking is not advice
 *    about walking; it is filler.
 *  - **One or two sentences, and short enough to read.**
 *
 * Anything rejected falls back to the template, which is always correct and merely dull. Returning
 * `null` says "keep what you have".
 */
export function acceptSuggestion(candidate: string, topic: string): string | null {
  const trimmed = candidate.trim().replace(/\s+/g, ' ');
  if (trimmed.length < 15 || trimmed.length > MAX_SUGGESTION_LENGTH) return null;
  if (statesEvidence(trimmed)) return null;

  // Matching is on whole words only. A `haystack.includes(topic)` fast path looks obviously
  // correct and is not: "steamed" contains "tea", so a suggestion about steaming vegetables would
  // pass as advice about tea. That is the same substring bug `topics.service.ts` was fixed for.
  const haystack = trimmed.toLowerCase();

  // A topic is a canonical phrase ("coca cola", "fruit and vegetables", "walking") and nobody
  // writes it that way in a sentence. So the check is per word and tolerant of inflection: "walk"
  // is advice about `walking`, and "cola" is advice about `coca cola`.
  const topicWords = topic
    .toLowerCase()
    .split(/\s+/)
    .filter((word) => word.length >= 3 && !TOPIC_CONNECTORS.has(word));
  const candidateWords = haystack.match(/[\p{L}]+/gu) ?? [];

  const mentionsTopic = topicWords.some((topicWord) =>
    candidateWords.some((word) => sharesStem(topicWord, word)),
  );
  return mentionsTopic ? trimmed : null;
}

/**
 * Words that only make sense as a claim about what the diary contains.
 *
 * A number beside any of these is the model quoting evidence it was never given. A number
 * anywhere else is a duration or a quantity in ordinary advice — "three days a week", "a ten
 * minute walk" — which costs nothing and often makes the suggestion more concrete.
 */
const EVIDENCE_WORDS =
  /\b(entry|entries|times|occasions|logged|recorded|journal|diary|percent)\b|%/iu;

function statesEvidence(text: string): boolean {
  if (/%|\bpercent\b/iu.test(text)) return true;
  return /\d/.test(text) && EVIDENCE_WORDS.test(text);
}

/** Words that carry no topic meaning; `fruit and vegetables` must not match on "and". */
const TOPIC_CONNECTORS = new Set(['and', 'the', 'of']);

/**
 * Whether two words are the same word wearing a different ending.
 *
 * Prefix matching on whole words, never on substrings — "tea" inside "steamed" is the exact bug
 * the topic extractor was fixed for, and it would be no less wrong here. The three-character
 * ceiling on the difference is what keeps "walk"/"walking" together while keeping "rest" and
 * "restaurant" apart.
 */
function sharesStem(a: string, b: string): boolean {
  const [shorter, longer] = a.length <= b.length ? [a, b] : [b, a];
  return shorter.length >= 3 && longer.length - shorter.length <= 3 && longer.startsWith(shorter);
}

/**
 * Ask the model to phrase one suggestion for a pattern the counting has already confirmed.
 *
 * It is told the topic, the feeling, and which way the insight points — and nothing else. No diary
 * text is sent: the advice follows from the correlation, not from the entries, so there is no
 * reason to hand over prose that does not improve the answer.
 */
async function ollamaSuggestion(
  topic: string,
  feelingKey: string,
  direction: string,
): Promise<string> {
  const config = loadConfig();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90_000);

  const intent =
    direction === 'keep'
      ? `The user tends to feel ${feelingKey} around ${topic}, and that is a good thing worth doing more of.`
      : `The user tends to feel ${feelingKey} around ${topic}, and that is worth changing or reducing.`;

  try {
    const response = await fetch(`${config.ollamaUrl}/api/chat`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model: config.ollamaModel,
        stream: false,
        think: false,
        keep_alive: 0,
        format: SUGGESTION_FORMAT,
        options: { temperature: 0.2, num_predict: 120 },
        messages: [
          {
            role: 'system',
            content:
              'You write one short, concrete suggestion for a personal mood diary, addressed to ' +
              'the person keeping it as "you". One or two sentences, under 180 characters. ' +
              'Suggest something they could actually do this week, and name the topic explicitly. ' +
              'Never say how many entries or how many times something happened — that count is ' +
              'shown separately and you have not been told it. A duration or a frequency in the ' +
              'advice itself is fine. ' +
              'Never claim to know why the correlation exists; it is an observation, not a cause. ' +
              'No greeting, no preamble, no diagnosis, no medical advice. Return only the schema. ' +
              // The example is deliberately about a topic nothing else in the app leans on. An
              // earlier version used walking-and-energised -- the same pair the evaluation grades
              // -- and the model simply echoed it back, so the eval was scoring the prompt rather
              // than the model. Keep this pair unrelated to whatever is being measured.
              'Example, for late screens and restless, worth reducing: "Try putting your phone in ' +
              'another room after dinner and see whether settling comes any easier."',
          },
          { role: 'user', content: intent },
        ],
      }),
    });
    if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}`);
    const body = (await response.json()) as OllamaChatResponse;
    return suggestionSchema.parse(JSON.parse(body.message?.content ?? '')).suggestion;
  } finally {
    clearTimeout(timeout);
    try {
      await fetch(`${config.ollamaUrl}/api/chat`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          model: config.ollamaModel,
          messages: [],
          stream: false,
          keep_alive: 0,
        }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      // The original narration error is the useful one.
    }
  }
}

interface UnnarratedPattern {
  id: string;
  /** The pattern's owner (#135) — read alongside everything else so the two `UPDATE`s below can be
   *  scoped to it once a candidate is picked; see {@link narrateNextPattern}'s doc comment. */
  user_id: string;
  topic: string;
  feeling_key: string;
  direction: string;
  suggestion_text: string;
  narration_attempts: number;
  narration_next_attempt_at: string | null;
}

/**
 * What one call to {@link narrateNextPattern} actually did (#88).
 *
 *  - `'wrote'` — a real suggestion replaced the template. The only outcome allowed to skip the
 *    worker loop's idle pacing (`runWorker`) — see there for why.
 *  - `'attempted'` — a pattern was tried and the model's answer was rejected, or the call itself
 *    failed. This branch *used to report success* (`return true`), which is root cause of #88: a
 *    rejected attempt has to pace exactly like idleness, never like progress.
 *  - `'idle'` — nothing was eligible to try: no pattern is still on the template, or every one
 *    that is has exhausted its attempts or is still backing off from its last one.
 */
export type NarrationOutcome = 'wrote' | 'attempted' | 'idle';

/** Doubles on every attempt and is capped, so a pattern's retries space out rather than repeating
 *  at a fixed interval forever. `attempts` is the attempt count *after* the one just made. */
function narrationBackoffMs(attempts: number): number {
  const scaled = NARRATION_BACKOFF_BASE_MS * 2 ** Math.max(0, attempts - 1);
  return Math.min(scaled, NARRATION_BACKOFF_MAX_MS);
}

/**
 * `now + backoff(attempts)`, in the same storage form every other timestamp in the diary uses
 * (`codecs.ts`). Fixed-width and zero-padded, so a plain string comparison — which is all
 * `narrateNextPattern`'s candidate query does — sorts identically to chronological order.
 */
function narrationBackoffTimestamp(attempts: number): string {
  const target = new Date(Date.now() + narrationBackoffMs(attempts));
  return encodeDateTime({
    year: target.getUTCFullYear(),
    month: target.getUTCMonth() + 1,
    day: target.getUTCDate(),
    hour: target.getUTCHours(),
    minute: target.getUTCMinutes(),
    second: target.getUTCSeconds(),
    microsecond: target.getUTCMilliseconds() * 1000,
  });
}

/**
 * #88 fix 5 (observability): one structured line per narration model call, so a busy worker and a
 * stuck one are distinguishable from the log alone — the incident that opened #88 had nothing to
 * look at but process tables and twenty minutes of guessing. Plain stderr, one JSON object per
 * line, matching the rest of the project's logging (`database.ts`, `migrate.ts`): no logging
 * dependency, no metrics server.
 */
function logNarrationAttempt(entry: {
  topic: string;
  feelingKey: string;
  outcome: 'accepted' | 'rejected' | 'error';
  durationMs: number;
  attempts: number;
  error?: string;
}): void {
  process.stderr.write(
    `${JSON.stringify({
      event: 'narration_attempt',
      topic: entry.topic,
      feeling_key: entry.feelingKey,
      outcome: entry.outcome,
      duration_ms: entry.durationMs,
      attempts: entry.attempts,
      ...(entry.error ? { error: entry.error } : {}),
    })}\n`,
  );
}

/**
 * Find one insight still carrying its placeholder advice and try to improve it.
 *
 * Patterns are narrated one at a time, in the background, and never on the request path: `GET
 * /insights` writes the template and returns immediately, so the view is never blank and never
 * waits on a cold model. The upgrade lands on a later read.
 *
 * #88: a pattern is eligible only while it is still on the template *and* has not exhausted
 * `MAX_NARRATION_ATTEMPTS` *and* is not still backing off from its last rejection
 * (`narration_next_attempt_at`). All three live as columns on `patterns` rather than in-memory
 * worker state, so they survive a restart — the original bug had nothing survive anywhere, which
 * is exactly why every idle tick started the same unbounded retry from scratch.
 *
 * Returns what actually happened, not merely whether something was tried — see {@link
 * NarrationOutcome}. `runWorker` uses that distinction to decide whether to pace like idleness.
 *
 * **Scoping (#135):** the candidate scan below is cross-user by design, the same reasoning as
 * `claimNext` — one query across every user's patterns rather than a loop that polls each user in
 * turn and multiplies query load by the user count. It is therefore deliberately left on the raw
 * connection rather than a `ScopedDb` handle, and it now also selects `p.user_id` so the two
 * `UPDATE`s below — which touch exactly the one pattern this call picked — can each be scoped to
 * that pattern's own owner via `ScopedDb.forUser`. The join to `topics` is pinned to the same
 * owner (`t.user_id = p.user_id`) so a pattern can never be narrated using another user's topic
 * row of the same id, even though `topic_id` already resolves to a single, globally-unique row on
 * its own — defence in depth, not a correctness fix.
 */
export async function narrateNextPattern(db: DiaryDatabase): Promise<NarrationOutcome> {
  const now = encodeDateTime(nowUtc());
  const candidate = db
    .prepare(
      `SELECT p.id, p.user_id, t.name AS topic, p.feeling_key, p.direction, p.suggestion_text,
              p.narration_attempts, p.narration_next_attempt_at
       FROM patterns p JOIN topics t ON t.id = p.topic_id AND t.user_id = p.user_id
       ORDER BY p.last_updated_at DESC, p.id`,
    )
    .all() as UnnarratedPattern[];

  // "Still the template" is the whole definition of un-narrated. A pattern whose count changed was
  // reset to the template — and its attempt state with it — by `recomputePatterns`, so it becomes
  // eligible again automatically.
  const pattern = candidate.find(
    (row) =>
      row.suggestion_text === templateSuggestionFor(row.feeling_key, row.topic) &&
      row.narration_attempts < MAX_NARRATION_ATTEMPTS &&
      (row.narration_next_attempt_at === null || row.narration_next_attempt_at <= now),
  );
  if (!pattern) return 'idle';

  const startedAt = Date.now();
  let written: string | null = null;
  let errorMessage: string | undefined;
  try {
    written = await ollamaSuggestion(pattern.topic, pattern.feeling_key, pattern.direction);
  } catch (error) {
    errorMessage = error instanceof Error ? error.message : 'Unknown narration error';
  }
  const durationMs = Date.now() - startedAt;
  const accepted = written === null ? null : acceptSuggestion(written, pattern.topic);
  const nextAttempts = pattern.narration_attempts + 1;

  if (accepted) {
    logNarrationAttempt({
      topic: pattern.topic,
      feelingKey: pattern.feeling_key,
      outcome: 'accepted',
      durationMs,
      attempts: nextAttempts,
    });
    // `last_updated_at` is deliberately untouched: rewording the advice is not the insight
    // changing, and stamping it here would reorder the user's Insights view for no reason they
    // could see. The attempt state resets — a pattern that just got narrated has nothing left to
    // retry until `recomputePatterns` next makes it eligible.
    createScopedDb(db)
      .forUser(pattern.user_id)
      .prepare(
        `UPDATE patterns SET suggestion_text = ?, narration_attempts = 0, narration_next_attempt_at = NULL
         WHERE id = ? AND suggestion_text = ? AND user_id = ?`,
      )
      .run(accepted, pattern.id, pattern.suggestion_text, pattern.user_id);
    return 'wrote';
  }

  // Tried, rejected — or the call itself failed — so the template stands. This is the fix for the
  // defect #88 describes: the old code reported this exact branch as "work done" (`return true`),
  // which let the worker loop skip its idle delay and call the model again immediately, on the
  // same pattern, forever. Recording the attempt and backing off is what makes a rejection pace
  // like idleness instead. The `narration_attempts = ?` clause is a cheap extra guard against a
  // second worker racing this same pattern — the primary defense is the singleton lock below.
  logNarrationAttempt({
    topic: pattern.topic,
    feelingKey: pattern.feeling_key,
    outcome: errorMessage ? 'error' : 'rejected',
    durationMs,
    attempts: nextAttempts,
    error: errorMessage,
  });
  createScopedDb(db)
    .forUser(pattern.user_id)
    .prepare(
      `UPDATE patterns SET narration_attempts = ?, narration_next_attempt_at = ?
       WHERE id = ? AND suggestion_text = ? AND narration_attempts = ? AND user_id = ?`,
    )
    .run(
      nextAttempts,
      narrationBackoffTimestamp(nextAttempts),
      pattern.id,
      pattern.suggestion_text,
      pattern.narration_attempts,
      pattern.user_id,
    );
  return 'attempted';
}

/** Words are the immutable payload; only casing, punctuation, whitespace and list markers vary. */
export function transcriptWordSequence(value: string): string[] {
  return value.toLocaleLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
}

export function acceptFormattedTranscript(original: string, candidate: string): string {
  const sameWords =
    JSON.stringify(transcriptWordSequence(original)) ===
    JSON.stringify(transcriptWordSequence(candidate));
  return sameWords && candidate.trim() ? candidate.trim() : original;
}

interface TranscriptToken {
  raw: string;
  normalized: string;
  start: number;
  end: number;
}

function transcriptTokens(value: string): TranscriptToken[] {
  return [...value.matchAll(/[\p{L}\p{N}]+/gu)].map((match) => ({
    raw: match[0],
    normalized: match[0].toLocaleLowerCase(),
    start: match.index,
    end: match.index + match[0].length,
  }));
}

/**
 * Treat the model output as a formatting stencil, never as prose. A small model edit is removed
 * by aligning its unchanged words to the source; only casing, punctuation and whitespace between
 * adjacent aligned words are copied. Large rewrites are rejected outright.
 */
export function projectTranscriptFormatting(original: string, candidate: string): string {
  const source = transcriptTokens(original);
  const formatted = transcriptTokens(candidate);
  if (!source.length || !formatted.length) return original;

  const width = formatted.length + 1;
  const cells = (source.length + 1) * width;
  if (cells > 2_000_000) return acceptFormattedTranscript(original, candidate);

  const lcs = new Uint32Array(cells);
  for (let sourceIndex = source.length - 1; sourceIndex >= 0; sourceIndex -= 1) {
    for (let formattedIndex = formatted.length - 1; formattedIndex >= 0; formattedIndex -= 1) {
      const cell = sourceIndex * width + formattedIndex;
      lcs[cell] =
        source[sourceIndex].normalized === formatted[formattedIndex].normalized
          ? 1 + lcs[(sourceIndex + 1) * width + formattedIndex + 1]
          : Math.max(
              lcs[(sourceIndex + 1) * width + formattedIndex],
              lcs[sourceIndex * width + formattedIndex + 1],
            );
    }
  }

  const aligned = new Map<number, number>();
  let sourceIndex = 0;
  let formattedIndex = 0;
  while (sourceIndex < source.length && formattedIndex < formatted.length) {
    if (source[sourceIndex].normalized === formatted[formattedIndex].normalized) {
      aligned.set(sourceIndex, formattedIndex);
      sourceIndex += 1;
      formattedIndex += 1;
    } else if (
      lcs[(sourceIndex + 1) * width + formattedIndex] >=
      lcs[sourceIndex * width + formattedIndex + 1]
    ) {
      sourceIndex += 1;
    } else {
      formattedIndex += 1;
    }
  }

  const editCount = source.length + formatted.length - 2 * aligned.size;
  // Small local models often try several grammar fixes in otherwise useful punctuation output.
  // A 20% edit-distance ceiling keeps that stencil usable; reconstruction below still emits
  // every source word, while a substantially rewritten or reordered response falls back intact.
  const toleratedEdits = Math.max(4, Math.ceil(source.length * 0.2));
  if (editCount > toleratedEdits) return original;

  let result =
    aligned.get(0) === 0
      ? candidate.slice(0, formatted[0].start)
      : original.slice(0, source[0].start);
  for (let index = 0; index < source.length; index += 1) {
    const alignedIndex = aligned.get(index);
    result += alignedIndex === undefined ? source[index].raw : formatted[alignedIndex].raw;

    const nextSource = source[index + 1];
    if (!nextSource) {
      result +=
        alignedIndex === formatted.length - 1
          ? candidate.slice(formatted[alignedIndex].end)
          : original.slice(source[index].end);
      continue;
    }

    const nextAlignedIndex = aligned.get(index + 1);
    result +=
      alignedIndex !== undefined && nextAlignedIndex === alignedIndex + 1
        ? candidate.slice(formatted[alignedIndex].end, formatted[nextAlignedIndex].start)
        : original.slice(source[index].end, nextSource.start);
  }

  const projected = result.trim();
  return acceptFormattedTranscript(original, projected) === projected ? projected : original;
}

/** Add scan-friendly paragraphs when the formatter leaves a long answer as one text wall. */
export function ensureTranscriptParagraphs(value: string): string {
  const totalWords = transcriptWordSequence(value).length;
  if (totalWords < 80 || /\n\s*\n/.test(value)) return value;

  const boundaries: Array<{ whitespaceStart: number; whitespaceEnd: number }> = [];
  const sentenceEnd = /[.!?]["'”’)]*(\s+)/g;
  let paragraphStart = 0;
  let consumedWords = 0;

  for (const match of value.matchAll(sentenceEnd)) {
    const whitespace = match[1];
    const whitespaceStart = match.index + match[0].length - whitespace.length;
    const boundaryWords = transcriptWordSequence(value.slice(0, whitespaceStart)).length;
    const paragraphWords = boundaryWords - consumedWords;
    const remainingWords = totalWords - boundaryWords;
    if (paragraphWords >= 45 && remainingWords >= 30) {
      boundaries.push({ whitespaceStart, whitespaceEnd: whitespaceStart + whitespace.length });
      paragraphStart = whitespaceStart + whitespace.length;
      consumedWords = transcriptWordSequence(value.slice(0, paragraphStart)).length;
    }
  }

  if (!boundaries.length) return value;
  let output = '';
  let cursor = 0;
  for (const boundary of boundaries) {
    output += value.slice(cursor, boundary.whitespaceStart).trimEnd() + '\n\n';
    cursor = boundary.whitespaceEnd;
  }
  output += value.slice(cursor).trimStart();
  return output;
}

async function ollamaFormatTranscript(transcript: string): Promise<string> {
  const config = loadConfig();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90_000);

  try {
    const response = await fetch(`${config.ollamaUrl}/api/chat`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model: config.ollamaModel,
        stream: false,
        think: false,
        keep_alive: 0,
        format: FORMATTED_TRANSCRIPT_FORMAT,
        options: { temperature: 0, num_predict: 1200 },
        messages: [
          {
            role: 'system',
            content:
              'You are a punctuation restoration engine. The input has had punctuation and ' +
              'layout removed. You MUST restore sentence-ending punctuation, commas where ' +
              'helpful, capitalization, and paragraph breaks at topic shifts. Do not merely copy ' +
              'the unpunctuated input. Preserve every word in exactly the same order and count. ' +
              'Never add, delete, replace, or reorder a word. Do not fix grammar, transcription ' +
              'errors, filler words, names, or meaning. Only punctuation, capitalization, ' +
              'whitespace, and Markdown list-marker characters may change. Use bullets only for ' +
              'a clearly spoken list. Example input: "i slept badly then work was difficult later ' +
              'i drank coffee tea and water". Example output: "I slept badly. Then work was ' +
              'difficult.\\n\\nLater, I drank:\\n- coffee\\n- tea\\n- and water." Return only ' +
              'the required schema.',
          },
          {
            role: 'user',
            content: `Restore punctuation and layout in this exact transcript:\n<transcript>\n${transcript}\n</transcript>`,
          },
        ],
      }),
    });
    if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}`);
    const body = (await response.json()) as OllamaChatResponse;
    const parsed = formattedTranscriptSchema.parse(JSON.parse(body.message?.content ?? ''));
    return ensureTranscriptParagraphs(
      projectTranscriptFormatting(transcript, parsed.formatted_text),
    );
  } finally {
    clearTimeout(timeout);
    try {
      await fetch(`${config.ollamaUrl}/api/chat`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          model: config.ollamaModel,
          messages: [],
          stream: false,
          keep_alive: 0,
        }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      // Keep the original formatting error.
    }
  }
}

/**
 * Applies a completed analysis, entirely within one user's rows (#135).
 *
 * `db` is always the handle `runWorker` obtained from `ScopedDb.forUser(job.userId)` — never the
 * raw connection — so every statement below both filters by `user_id = job.userId` (a `SELECT`,
 * `UPDATE` or `DELETE`) and sets it (an `INSERT`'s column list), which is also what lets each
 * statement pass `ScopedDb`'s guard at all. `topics.UNIQUE (user_id, name)` (`schema.ts`) is why
 * `findTopic` filters on both: two different users can genuinely each have their own "coffee".
 */
function applyAnalysis(db: DiaryDatabase, job: Job, analysis: EntryAnalysis): void {
  db.transaction(() => {
    const now = encodeDateTime(nowUtc());
    const entryStillExists = db
      .prepare('SELECT 1 FROM diary_entries WHERE id = ? AND user_id = ?')
      .get(job.entryId, job.userId);
    if (!entryStillExists) {
      db.prepare(
        `UPDATE inference_jobs SET status = 'failed', error_text = 'Entry no longer exists',
         completed_at = ? WHERE id = ? AND user_id = ?`,
      ).run(now, job.id, job.userId);
      return;
    }

    // The set and the primary feeling are written together, and only while the user has not
    // spoken: `feeling_source = 'unset'` is the whole guard. An entry whose feelings the user
    // already confirmed keeps them, and the fresh suggestion survives in the job row below for a
    // client to offer.
    const applied = db
      .prepare(
        `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
         WHERE id = ? AND feeling_source = 'unset' AND user_id = ?`,
      )
      .run(analysis.feelings[0].key, now, job.entryId, job.userId);
    if (applied.changes === 1) {
      db.prepare('DELETE FROM entry_feelings WHERE entry_id = ? AND user_id = ?').run(
        job.entryId,
        job.userId,
      );
      const insertFeeling = db.prepare(
        'INSERT INTO entry_feelings (entry_id, user_id, feeling_key, position) VALUES (?, ?, ?, ?)',
      );
      analysis.feelings.forEach((feeling, position) =>
        insertFeeling.run(job.entryId, job.userId, feeling.key, position),
      );
    }

    const findTopic = db.prepare('SELECT id FROM topics WHERE name = ? AND user_id = ?');
    const insertTopic = db.prepare(
      `INSERT INTO topics (id, user_id, name, aliases, first_seen_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    );
    const touchTopic = db.prepare('UPDATE topics SET last_seen_at = ? WHERE id = ? AND user_id = ?');
    const linkTopic = db.prepare(
      `INSERT OR IGNORE INTO entry_topics (entry_id, topic_id, user_id, extracted_by)
       VALUES (?, ?, ?, 'llm')`,
    );

    // A4-02: the proposal is mapped onto a canonical topic *before* a row is touched. Storing it
    // first and merging later is what produced the diary full of one-shot near-synonyms the audit
    // found — "project review", "project meeting" and "review" as three rows, none of which ever
    // reached three occurrences. A proposal that matches nothing is still stored under its own
    // name: the mapping is a preference, not a filter (A4-10).
    //
    // Scoped to this job's own user (#135): the vocabulary a proposal canonicalises against is
    // this user's own topic list only. Reading across users here would let one user's topic names
    // (and aliases) steer another user's canonicalization — the same class of leak this ticket
    // exists to close, just via a read instead of a write.
    const known = (
      db.prepare('SELECT name, aliases FROM topics WHERE user_id = ? ORDER BY name').all(
        job.userId,
      ) as Array<{
        name: string;
        aliases: string;
      }>
    ).map((row) => ({ name: row.name, aliases: decodeJson<string[]>(row.aliases ?? '[]') }));

    const canonical = new Set<string>();
    // Which canonical topic a *proposed* phrase resolved to — kept so the pairings below (which
    // name a proposed phrase, per `EntryAnalysis.pairings`) can be resolved to the same topic id
    // this loop is about to create or reuse, without re-running canonicalization a second time.
    const canonicalByProposed = new Map<string, string>();
    for (const proposed of analysis.topics) {
      const resolved = canonicalTopicName(proposed, known);
      if (resolved) {
        canonical.add(resolved);
        canonicalByProposed.set(proposed, resolved);
      }
    }

    const topicIdByName = new Map<string, string>();
    for (const name of canonical) {
      const existing = findTopic.get(name, job.userId) as { id: string } | undefined;
      const topicId = existing?.id ?? randomUUID();
      if (existing) touchTopic.run(now, topicId, job.userId);
      else {
        insertTopic.run(topicId, job.userId, name, encodeJson([]), now, now);
        known.push({ name, aliases: [] });
      }
      linkTopic.run(job.entryId, topicId, job.userId);
      topicIdByName.set(name, topicId);
    }

    // E-1a: store each surviving pairing as a *suggestion* — never a silent overwrite. The guard
    // mirrors the feelings guard above: a pairing the user has already confirmed or overridden
    // stays exactly as the user left it, because `applyAnalysis` runs once against an entry whose
    // `entry_topic_feelings` rows started this pass empty (a fresh entry, or one whose text just
    // changed and had every prior row cleared with it) — the guard exists for the rarer case of a
    // second analysis job somehow landing on the same rows, not for the common path.
    if (analysis.pairings.length > 0) {
      const alreadyDecided = new Set(
        (
          db
            .prepare(
              `SELECT topic_id, feeling_key FROM entry_topic_feelings
               WHERE entry_id = ? AND source != 'suggested' AND user_id = ?`,
            )
            .all(job.entryId, job.userId) as Array<{ topic_id: string; feeling_key: string }>
        ).map((row) => `${row.topic_id} ${row.feeling_key}`),
      );
      const insertPairing = db.prepare(
        `INSERT OR IGNORE INTO entry_topic_feelings (entry_id, topic_id, user_id, feeling_key, source)
         VALUES (?, ?, ?, ?, 'suggested')`,
      );
      for (const pairing of analysis.pairings) {
        const canonicalName = canonicalByProposed.get(pairing.topic);
        const topicId = canonicalName ? topicIdByName.get(canonicalName) : undefined;
        if (!topicId) continue;
        for (const feelingKey of pairing.feelingKeys) {
          if (alreadyDecided.has(`${topicId} ${feelingKey}`)) continue;
          insertPairing.run(job.entryId, topicId, job.userId, feelingKey);
        }
      }
    }

    // The completed row is kept rather than deleted, because it is the only place the *suggested*
    // feeling survives: the UPDATE above applies it only while `feeling_source = 'unset'`, so for an
    // entry whose feeling the user already confirmed, the fresh suggestion would otherwise be
    // computed and thrown away. Clients read it back to propose a change after an edit.
    //
    // Growth stays bounded by pruning this entry's older analysis rows -- at most one survives per
    // entry, which is what the original DELETE was protecting against.
    db.prepare(
      `UPDATE inference_jobs SET status = 'completed', result_json = ?, completed_at = ?
       WHERE id = ? AND user_id = ?`,
    ).run(
      // `feeling_key`/`confidence` are still written alongside the list. They are what a client
      // built before the vocabulary grew reads, and what `readSuggestedFeelings` falls back to.
      JSON.stringify({
        feeling_key: analysis.feelings[0].key,
        confidence: analysis.feelings[0].confidence,
        feelings: analysis.feelings,
      }),
      now,
      job.id,
      job.userId,
    );
    db.prepare(
      `DELETE FROM inference_jobs
       WHERE entry_id = ? AND kind = 'entry_analysis' AND id <> ? AND user_id = ?`,
    ).run(job.entryId, job.id, job.userId);
  });
}

/**
 * Runs the model call and applies its result, all within one user's rows (#135).
 *
 * `db` is the handle `runWorker` obtained from `ScopedDb.forUser(job.userId)` for this specific
 * job — see `applyAnalysis`'s doc comment for what that guarantees and what it does not.
 */
async function processJob(db: DiaryDatabase, job: Job): Promise<void> {
  if (job.kind === 'transcript_format') {
    const payload = JSON.parse(job.resultJson ?? '{}') as { input?: unknown };
    if (typeof payload.input !== 'string') throw new Error('Formatting job has no transcript');
    const text = await ollamaFormatTranscript(payload.input);
    db.prepare(
      `UPDATE inference_jobs SET status = 'completed', result_json = ?, completed_at = ?
       WHERE id = ? AND user_id = ?`,
    ).run(JSON.stringify({ text }), encodeDateTime(nowUtc()), job.id, job.userId);
    return;
  }

  const entry = db
    .prepare('SELECT raw_text FROM diary_entries WHERE id = ? AND user_id = ?')
    .get(job.entryId, job.userId) as { raw_text: string } | undefined;
  if (!entry) throw new Error('Entry no longer exists');
  const analysis = await ollamaAnalysis(entry.raw_text);
  if (analysis.feelings.length === 0) throw new Error('Analysis proposed no feeling');
  applyAnalysis(db, job, analysis);
}

/** `db` is the same per-job `ScopedDb.forUser(job.userId)` handle `processJob` used (#135). */
function recordFailure(db: DiaryDatabase, job: Job, error: unknown): void {
  const message = error instanceof Error ? error.message.slice(0, 500) : 'Unknown inference error';
  const retry = job.attempts < 3;
  db.prepare(
    `UPDATE inference_jobs SET status = ?, error_text = ?, completed_at = ?, started_at = NULL
     WHERE id = ? AND user_id = ?`,
  ).run(
    retry ? 'queued' : 'failed',
    message,
    retry ? null : encodeDateTime(nowUtc()),
    job.id,
    job.userId,
  );
}

/**
 * #88 fix 4: a PID lock file beside the diary, so a second worker process exits instead of racing
 * the first one for the same jobs and patterns.
 *
 * `claimNext` already guards `inference_jobs` with a conditional `UPDATE ... WHERE status =
 * 'queued'`, so two workers never both apply the same analysis job -- but `narrateNextPattern` had
 * no equivalent guard, which is the aggravating factor the incident's root-cause analysis called
 * out separately (§2f): nothing stopped two or three worker processes, left running from repeated
 * restarts during a seeding session, from all calling the model for the *same* un-narrated pattern
 * before any one of their writes landed. One worker per diary, enforced here, removes that race
 * outright instead of only making the final write safe.
 *
 * The lock lives next to the diary file rather than in a fixed system location, so two diaries on
 * one machine -- a real one and a throwaway test fixture, say -- never contend for the same lock.
 */
function workerLockPath(databasePath: string): string {
  return `${databasePath}.worker.lock`;
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    // EPERM means the process exists but is owned by someone else -- still alive, just not ours to
    // signal. Anything else (ESRCH, or a PID that was never valid) means it is not.
    return (error as NodeJS.ErrnoException).code === 'EPERM';
  }
}

export interface WorkerLock {
  release: () => void;
}

/**
 * Exclusive-create the lock file (`wx`) so acquiring it is atomic even against a second process
 * doing the same thing at the same instant. `EEXIST` means the file is already there -- unless the
 * PID written inside it is no longer running, in which case the previous holder crashed or was
 * killed without cleaning up, and the lock is stale and safe to take over.
 *
 * Returns `null` when a live process already holds the lock. The caller's job is to log and exit,
 * never to retry: a second worker is not queued behind the first, it simply has nothing to do.
 */
export function acquireWorkerLock(databasePath: string): WorkerLock | null {
  const lockPath = workerLockPath(databasePath);
  try {
    const fd = fs.openSync(lockPath, 'wx');
    fs.writeSync(fd, String(process.pid));
    fs.closeSync(fd);
    return { release: () => releaseWorkerLock(lockPath) };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
  }

  let holderPid: number | null = null;
  try {
    const parsed = Number(fs.readFileSync(lockPath, 'utf8').trim());
    holderPid = Number.isInteger(parsed) ? parsed : null;
  } catch {
    // Unreadable lock file -- treated the same as a stale one below.
  }
  if (holderPid !== null && isProcessAlive(holderPid)) return null;

  // Stale lock: the file exists but nothing is listening on that PID any more. Take it over --
  // a plain write, not an exclusive create, since the file is already there.
  fs.writeFileSync(lockPath, String(process.pid));
  return { release: () => releaseWorkerLock(lockPath) };
}

function releaseWorkerLock(lockPath: string): void {
  try {
    fs.unlinkSync(lockPath);
  } catch {
    // Already gone -- nothing left to clean up.
  }
}

/**
 * @param signal Lets a caller stop the long-running form (`once = false`) without sending a real
 * process signal, which in a test would tear down the whole test process rather than just this
 * worker. `SIGTERM`/`SIGINT` above remain how the compiled binary is actually stopped; this is
 * purely an in-process escape hatch for tests that need to run the real loop for a bounded stretch.
 */
export async function runWorker(once = false, signal?: AbortSignal): Promise<void> {
  const config = loadConfig();

  // #88 fix 4: refuse to run alongside another worker on the same diary rather than competing with
  // it for jobs and patterns.
  const lock = acquireWorkerLock(config.databasePath);
  if (!lock) {
    process.stderr.write(
      `Inference worker: another worker already holds the lock for ${config.databasePath}; exiting.\n`,
    );
    return;
  }

  const db = openDiary(config.databasePath);
  assertCompatible(db);
  const scopedDb = createScopedDb(db);

  // A process killed during inference leaves no ambiguous result: its job becomes retryable.
  //
  // Deliberately unscoped (#135): this is process-restart bookkeeping, not work done on behalf of
  // any one user — a worker that crashed mid-job may have left *any* user's row stuck in
  // 'running', and recovering all of them in one cross-user sweep is the entire point. There is no
  // single `userId` this could be scoped to without turning one restart-time pass into a per-user
  // loop, which is exactly the multiplied query cost criterion 4 forbids, for a maintenance step
  // that only ever runs once per process start, never per poll.
  db.prepare(
    `UPDATE inference_jobs SET status = 'queued', started_at = NULL
     WHERE status = 'running' AND attempts < 3`,
  ).run();
  db.prepare(
    `UPDATE inference_jobs SET status = 'failed', completed_at = ?
     WHERE status = 'running' AND attempts >= 3`,
  ).run(encodeDateTime(nowUtc()));

  let stopping = false;
  // Only the long-running form needs to listen for a shutdown signal. A one-shot run has nothing
  // to interrupt, and registering handlers it will never use leaks a listener per call -- which a
  // test that drains the queue job by job hits within a few entries.
  if (!once) {
    process.once('SIGTERM', () => {
      stopping = true;
    });
    process.once('SIGINT', () => {
      stopping = true;
    });
  }
  if (signal) {
    if (signal.aborted) stopping = true;
    else
      signal.addEventListener(
        'abort',
        () => {
          stopping = true;
        },
        { once: true },
      );
  }

  // #88 fix 3: the token bucket for narration. `0` until the first attempt, so the very first idle
  // tick may narrate immediately -- only the *spacing between calls* is throttled, never the first
  // one.
  let lastNarrationCallAt = 0;

  try {
    do {
      const job = claimNext(db);
      if (job) {
        // Everything downstream of a claimed job runs against a handle scoped to that job's own
        // owner (#135) — the raw connection is never touched again for this job.
        const userDb = scopedDb.forUser(job.userId);
        try {
          await processJob(userDb, job);
        } catch (error) {
          recordFailure(userDb, job, error);
        }
        if (once) break;
        continue;
      }

      // Narration is strictly lower priority than analysis: an entry the user just wrote is
      // waiting on its feeling, while an insight already reads correctly and is only waiting to
      // read better. So it happens only when the queue is empty -- `claimNext` above is re-checked
      // on every iteration, which is what lets a job queued mid-narration preempt on the very next
      // tick -- and even then it is budgeted to at most one model call per
      // `NARRATION_MIN_INTERVAL_MS`, regardless of outcome: a written suggestion is exactly as
      // throttled as a rejected one, so a diary with fifty un-narrated patterns cannot burn
      // through the model back-to-back either.
      let outcome: NarrationOutcome = 'idle';
      if (Date.now() - lastNarrationCallAt >= NARRATION_MIN_INTERVAL_MS) {
        outcome = await narrateNextPattern(db);
        if (outcome !== 'idle') lastNarrationCallAt = Date.now();
      }

      if (once) break;
      // Only a real write skips the pacing delay. A rejected attempt, an errored call, and true
      // idleness all wait the same 400ms -- the fix for #88's root cause, which let a rejected
      // attempt report itself as "work done" and spin on the same pattern with no delay at all.
      if (outcome !== 'wrote') await delay(400);
    } while (!stopping);
  } finally {
    lock.release();
    db.close();
  }
}

if (require.main === module) {
  void runWorker(process.argv.includes('--once')).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : 'Unknown worker error';
    process.stderr.write(`Inference worker failed: ${message}\n`);
    process.exitCode = 1;
  });
}
