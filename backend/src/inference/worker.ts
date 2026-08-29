import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { loadConfig } from '../config';
import { assertCompatible } from '../db/compatibility';
import { decodeJson, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { openDiary, type DiaryDatabase } from '../db/database';
import { canonicalTopicName, normalizeTopicName } from '../topics/canonicalization';
import { CURATED_TOPIC_KEYWORDS } from '../topics/topics.service';
import { templateSuggestionFor } from '../insights/patterns.service';
import {
  FEELING_GROUP_SEED,
  FEELING_GROUP_KEYS,
  FEELING_KEYS,
  FEELING_SEED,
  GROUP_BY_FEELING_KEY,
  MAX_FEELINGS_PER_ENTRY,
} from '../db/feeling-vocabulary';
import { type EntryAnalysis } from './inference';

interface Job {
  id: string;
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
  },
  required: ['feelings', 'topics'],
  additionalProperties: false,
} as const;

const delay = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function claimNext(db: DiaryDatabase): Job | null {
  return db.transaction(() => {
    const row = db
      .prepare(
        `SELECT id, kind, entry_id, attempts, result_json FROM inference_jobs
         WHERE status = 'queued' AND kind IN ('entry_analysis', 'transcript_format')
         ORDER BY created_at, id LIMIT 1`,
      )
      .get() as
      | {
          id: string;
          kind: 'entry_analysis' | 'transcript_format';
          entry_id: string;
          attempts: number;
          result_json: string | null;
        }
      | undefined;
    if (!row) return null;

    const changed = db
      .prepare(
        `UPDATE inference_jobs SET status = 'running', attempts = attempts + 1,
         started_at = ?, error_text = NULL WHERE id = ? AND status = 'queued'`,
      )
      .run(encodeDateTime(nowUtc()), row.id);
    if (changed.changes !== 1) return null;
    return {
      id: row.id,
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
        // Raised from 220: the response now carries up to four feeling objects alongside the
        // topics, and a truncated response is a parse failure, not a shorter answer.
        options: { temperature: 0, num_predict: 400 },
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
              'For anything else use a short, lowercase, stable noun phrase. Return only the schema.',
          },
          { role: 'user', content: text },
        ],
      }),
    });
    if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}`);
    const body = (await response.json()) as OllamaChatResponse;
    const parsed = modelOutputSchema.parse(JSON.parse(body.message?.content ?? ''));
    return {
      feelings: reconcileFeelings(parsed.feelings),
      topics: normalizeTopics(parsed.topics),
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
  topic: string;
  feeling_key: string;
  direction: string;
  suggestion_text: string;
}

/**
 * Find one insight still carrying its placeholder advice and try to improve it.
 *
 * Patterns are narrated one at a time, in the background, and never on the request path: `GET
 * /insights` writes the template and returns immediately, so the view is never blank and never
 * waits on a cold model. The upgrade lands on a later read.
 *
 * Returns whether there was anything to do, so the worker loop can tell work from idleness.
 */
export async function narrateNextPattern(db: DiaryDatabase): Promise<boolean> {
  const candidate = db
    .prepare(
      `SELECT p.id, t.name AS topic, p.feeling_key, p.direction, p.suggestion_text
       FROM patterns p JOIN topics t ON t.id = p.topic_id
       ORDER BY p.last_updated_at DESC, p.id`,
    )
    .all() as UnnarratedPattern[];

  // "Still the template" is the whole definition of un-narrated. A pattern whose count changed was
  // reset to the template by `recomputePatterns`, so it becomes eligible again automatically.
  const pattern = candidate.find(
    (row) => row.suggestion_text === templateSuggestionFor(row.feeling_key, row.topic),
  );
  if (!pattern) return false;

  const written = await ollamaSuggestion(pattern.topic, pattern.feeling_key, pattern.direction);
  const accepted = acceptSuggestion(written, pattern.topic);
  if (!accepted) return true; // Tried, rejected; the template stands. Still counts as work done.

  // `last_updated_at` is deliberately untouched: rewording the advice is not the insight changing,
  // and stamping it here would reorder the user's Insights view for no reason they could see.
  db.prepare('UPDATE patterns SET suggestion_text = ? WHERE id = ? AND suggestion_text = ?').run(
    accepted,
    pattern.id,
    pattern.suggestion_text,
  );
  return true;
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

function applyAnalysis(db: DiaryDatabase, job: Job, analysis: EntryAnalysis): void {
  db.transaction(() => {
    const now = encodeDateTime(nowUtc());
    const entryStillExists = db
      .prepare('SELECT 1 FROM diary_entries WHERE id = ?')
      .get(job.entryId);
    if (!entryStillExists) {
      db.prepare(
        `UPDATE inference_jobs SET status = 'failed', error_text = 'Entry no longer exists',
         completed_at = ? WHERE id = ?`,
      ).run(now, job.id);
      return;
    }

    // The set and the primary feeling are written together, and only while the user has not
    // spoken: `feeling_source = 'unset'` is the whole guard. An entry whose feelings the user
    // already confirmed keeps them, and the fresh suggestion survives in the job row below for a
    // client to offer.
    const applied = db
      .prepare(
        `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
         WHERE id = ? AND feeling_source = 'unset'`,
      )
      .run(analysis.feelings[0].key, now, job.entryId);
    if (applied.changes === 1) {
      db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(job.entryId);
      const insertFeeling = db.prepare(
        'INSERT INTO entry_feelings (entry_id, feeling_key, position) VALUES (?, ?, ?)',
      );
      analysis.feelings.forEach((feeling, position) =>
        insertFeeling.run(job.entryId, feeling.key, position),
      );
    }

    const findTopic = db.prepare('SELECT id FROM topics WHERE name = ?');
    const insertTopic = db.prepare(
      `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?)`,
    );
    const touchTopic = db.prepare('UPDATE topics SET last_seen_at = ? WHERE id = ?');
    const linkTopic = db.prepare(
      `INSERT OR IGNORE INTO entry_topics (entry_id, topic_id, extracted_by)
       VALUES (?, ?, 'llm')`,
    );

    // A4-02: the proposal is mapped onto a canonical topic *before* a row is touched. Storing it
    // first and merging later is what produced the diary full of one-shot near-synonyms the audit
    // found — "project review", "project meeting" and "review" as three rows, none of which ever
    // reached three occurrences. A proposal that matches nothing is still stored under its own
    // name: the mapping is a preference, not a filter (A4-10).
    const known = (
      db.prepare('SELECT name, aliases FROM topics ORDER BY name').all() as Array<{
        name: string;
        aliases: string;
      }>
    ).map((row) => ({ name: row.name, aliases: decodeJson<string[]>(row.aliases ?? '[]') }));

    const canonical = new Set<string>();
    for (const proposed of analysis.topics) {
      const resolved = canonicalTopicName(proposed, known);
      if (resolved) canonical.add(resolved);
    }

    for (const name of canonical) {
      const existing = findTopic.get(name) as { id: string } | undefined;
      const topicId = existing?.id ?? randomUUID();
      if (existing) touchTopic.run(now, topicId);
      else {
        insertTopic.run(topicId, name, encodeJson([]), now, now);
        known.push({ name, aliases: [] });
      }
      linkTopic.run(job.entryId, topicId);
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
       WHERE id = ?`,
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
    );
    db.prepare(
      `DELETE FROM inference_jobs
       WHERE entry_id = ? AND kind = 'entry_analysis' AND id <> ?`,
    ).run(job.entryId, job.id);
  });
}

async function processJob(db: DiaryDatabase, job: Job): Promise<void> {
  if (job.kind === 'transcript_format') {
    const payload = JSON.parse(job.resultJson ?? '{}') as { input?: unknown };
    if (typeof payload.input !== 'string') throw new Error('Formatting job has no transcript');
    const text = await ollamaFormatTranscript(payload.input);
    db.prepare(
      `UPDATE inference_jobs SET status = 'completed', result_json = ?, completed_at = ?
       WHERE id = ?`,
    ).run(JSON.stringify({ text }), encodeDateTime(nowUtc()), job.id);
    return;
  }

  const entry = db.prepare('SELECT raw_text FROM diary_entries WHERE id = ?').get(job.entryId) as
    { raw_text: string } | undefined;
  if (!entry) throw new Error('Entry no longer exists');
  const analysis = await ollamaAnalysis(entry.raw_text);
  if (analysis.feelings.length === 0) throw new Error('Analysis proposed no feeling');
  applyAnalysis(db, job, analysis);
}

function recordFailure(db: DiaryDatabase, job: Job, error: unknown): void {
  const message = error instanceof Error ? error.message.slice(0, 500) : 'Unknown inference error';
  const retry = job.attempts < 3;
  db.prepare(
    `UPDATE inference_jobs SET status = ?, error_text = ?, completed_at = ?, started_at = NULL
     WHERE id = ?`,
  ).run(retry ? 'queued' : 'failed', message, retry ? null : encodeDateTime(nowUtc()), job.id);
}

export async function runWorker(once = false): Promise<void> {
  const config = loadConfig();
  const db = openDiary(config.databasePath);
  assertCompatible(db);

  // A process killed during inference leaves no ambiguous result: its job becomes retryable.
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

  try {
    do {
      const job = claimNext(db);
      if (job) {
        try {
          await processJob(db, job);
        } catch (error) {
          recordFailure(db, job, error);
        }
        if (once) break;
        continue;
      }

      // Narration is strictly lower priority than analysis: an entry the user just wrote is
      // waiting on its feeling, while an insight already reads correctly and is only waiting to
      // read better. So it happens only when the queue is empty.
      let narrated = false;
      try {
        narrated = await narrateNextPattern(db);
      } catch {
        // A failed narration costs nothing -- the template is still in place and the pattern stays
        // eligible, so the next idle moment tries again. Nothing to record and nothing to retry.
      }
      if (once) break;
      if (!narrated) await delay(400);
    } while (!stopping);
  } finally {
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
