import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { loadConfig } from '../config';
import { assertCompatible } from '../db/compatibility';
import { encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { openDiary, type DiaryDatabase } from '../db/database';
import { CURATED_TOPIC_KEYWORDS } from '../topics/topics.service';
import { FEELING_KEYS, type EntryAnalysis } from './inference';

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

const modelOutputSchema = z.object({
  feeling_key: z.enum(FEELING_KEYS),
  confidence: z.number().min(0).max(1),
  topics: z.array(z.string()).max(10),
});

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
    feeling_key: { type: 'string', enum: FEELING_KEYS },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    topics: {
      type: 'array',
      maxItems: 10,
      items: { type: 'string', minLength: 2, maxLength: 40 },
    },
  },
  required: ['feeling_key', 'confidence', 'topics'],
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

function normalizeTopics(values: string[]): string[] {
  const ignored = new Set<string>([...FEELING_KEYS, 'feeling', 'feelings', 'mood', 'today']);
  const normalized = values
    .map((value) =>
      value
        .trim()
        .toLowerCase()
        .replace(/[^\p{L}\p{N} -]/gu, '')
        .replace(/\s+/g, ' '),
    )
    .filter((value) => value.length >= 2 && value.length <= 40 && !ignored.has(value));
  return [...new Set(normalized)].slice(0, 10);
}

async function ollamaAnalysis(text: string): Promise<EntryAnalysis> {
  const config = loadConfig();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90_000);
  const canonicalTopics = Object.keys(CURATED_TOPIC_KEYWORDS).join(', ');

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
        options: { temperature: 0, num_predict: 220 },
        messages: [
          {
            role: 'system',
            content:
              'Analyze one private diary entry. Choose exactly one feeling from the schema. ' +
              'Extract concrete, reusable factors that could correlate with that feeling: ' +
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
      feeling: { key: parsed.feeling_key, confidence: parsed.confidence },
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

    db.prepare(
      `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
       WHERE id = ? AND feeling_source = 'unset'`,
    ).run(analysis.feeling.key, now, job.entryId);

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

    for (const name of analysis.topics) {
      const existing = findTopic.get(name) as { id: string } | undefined;
      const topicId = existing?.id ?? randomUUID();
      if (existing) touchTopic.run(now, topicId);
      else insertTopic.run(topicId, name, encodeJson([]), now, now);
      linkTopic.run(job.entryId, topicId);
    }

    // The entry is the durable result observed by clients. Once that update commits, retaining a
    // completed queue row would only grow the database forever now that no HTTP waiter consumes it.
    db.prepare('DELETE FROM inference_jobs WHERE id = ?').run(job.id);
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
  process.once('SIGTERM', () => {
    stopping = true;
  });
  process.once('SIGINT', () => {
    stopping = true;
  });

  try {
    do {
      const job = claimNext(db);
      if (!job) {
        if (once) break;
        await delay(400);
        continue;
      }
      try {
        await processJob(db, job);
      } catch (error) {
        recordFailure(db, job, error);
      }
      if (once) break;
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
