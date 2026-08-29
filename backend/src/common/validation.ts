import { HttpException, HttpStatus } from '@nestjs/common';
import { z, type ZodType } from 'zod';
import { FEELING_KEYS, MAX_FEELINGS_PER_ENTRY } from '../db/feeling-vocabulary';
import { MAX_INTENSITY, MIN_INTENSITY } from '../insights/constants';
import { MAX_EXPERIMENT_LENGTH_DAYS, MIN_EXPERIMENT_LENGTH_DAYS } from '../experiments/constants';

/**
 * Request validation.
 *
 * The status is the point: a missing or malformed field answers **422**, which is what the contract
 * tests and both clients expect. NestJS's `ValidationPipe` defaults to **400**, so it is set
 * explicitly here rather than inherited (contracts/api.md).
 */
export function parseOrThrow<S extends ZodType>(schema: S, value: unknown): z.output<S> {
  const result = schema.safeParse(value);
  if (!result.success) {
    const detail = result.error.issues
      .map((issue) => `${issue.path.join('.') || '(body)'}: ${issue.message}`)
      .join('; ');
    throw new HttpException(detail, HttpStatus.UNPROCESSABLE_ENTITY);
  }
  return result.data;
}

export const guidedAnswerSchema = z.object({
  question_key: z.string(),
  answer_text: z.string(),
});

export const entryCreateSchema = z.object({
  mode: z.enum(['guided', 'freeform']).default('freeform'),
  raw_text: z.string().default(''),
  guided_answers: z.array(guidedAnswerSchema).default([]),
});

/**
 * `version` is required — without it there is no way to tell a deliberate edit from a stale one.
 *
 * `feeling_key` and `feeling_keys` both stay accepted. The single-key form is what a client built
 * before the vocabulary grew sends, and rejecting it would break that client for no gain — the
 * service reads it as a set of one. Sending both is not an error either; `feeling_keys` wins.
 *
 * The list is capped at the same ceiling the analyser is held to: a user may tag an entry with as
 * many feelings as the app is willing to propose, and no more.
 */
export const entryUpdateSchema = z.object({
  raw_text: z.string().nullish(),
  feeling_key: z.enum(FEELING_KEYS).nullish(),
  feeling_keys: z.array(z.enum(FEELING_KEYS)).max(MAX_FEELINGS_PER_ENTRY).nullish(),
  /**
   * The optional intensity dial on the primary feeling (I6-01).
   *
   * Three states, all meaningful and all different: absent means "leave whatever is stored",
   * `null` means "clear it", and 1–5 sets it. Collapsing absent and null would make every
   * feeling-only edit silently erase an intensity the user set earlier (I6-03).
   */
  feeling_intensity: z.number().int().min(MIN_INTENSITY).max(MAX_INTENSITY).nullable().optional(),
  /**
   * The dial as it now works: one optional rating per feeling on the entry, keyed by feeling key.
   *
   * The single-value [feeling_intensity] above stays accepted and means a rating of the primary
   * feeling — that is what a client built before the dial moved sends. Sending both is not an
   * error; this map wins, because it is the form that can express the whole answer.
   *
   * Absent leaves the stored ratings alone; a map (including an empty one) replaces them outright,
   * which is how a rating is cleared.
   */
  feeling_intensities: z
    .record(z.enum(FEELING_KEYS), z.number().int().min(MIN_INTENSITY).max(MAX_INTENSITY))
    .nullish(),
  version: z.number().int(),
});

export const versionQuerySchema = z.coerce.number().int();

/**
 * One user-confirmed or user-overridden topic↔feeling pairing (E-1a).
 *
 * `source` is deliberately absent — it is derived server-side, from comparison against what the
 * worker last suggested, the same way `feeling_source` is derived from `feeling_keys` rather than
 * sent by the client. `feeling_key` is checked against the whole vocabulary here; whether it is
 * actually a feeling *on this entry* is a per-entry fact only `EntriesService` can check.
 */
export const topicFeelingPairingInputSchema = z.object({
  topic_id: z.string().trim().min(1),
  feeling_key: z.enum(FEELING_KEYS),
});

/**
 * The whole set replaces whatever pairings were stored for the entry (E-1a) — the same
 * overwrite-the-set contract `feeling_keys` already has on `PATCH /entries/{id}`, not a
 * per-pairing patch. An empty array is a legitimate answer: "none of these topics pair with a
 * feeling" is exactly what task 1 calls "fine and common".
 */
export const topicFeelingsUpdateSchema = z.object({
  pairings: z.array(topicFeelingPairingInputSchema).max(40),
});

/** One user-added spelling of a topic (A4-04). Length matches the `topics.name` column. */
export const topicAliasSchema = z.object({
  alias: z.string().trim().min(1).max(128),
});

export const guidedDraftAnswerSchema = z.object({
  answer_text: z.string().trim().min(1),
  order_index: z.number().int().min(0).max(100),
});

export const orderIndexQuerySchema = z.coerce.number().int().min(0).max(100);

/**
 * A calendar date, `YYYY-MM-DD`. Only the shape is checked here; a value that is the right shape
 * but not a real date (`2026-02-30`) is rejected downstream by `decodeDate`, the one place a date
 * string is actually parsed (`db/codecs.ts`).
 */
const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'expected YYYY-MM-DD');

/**
 * Starting an experiment from a qualifying pattern (R-3a). `pattern_topic` and `pattern_feeling`
 * identify the pattern the same way the client already has it — the exact `topic` and `feeling`
 * strings off a `PatternOut` from `GET /insights` — so no separate lookup id is needed. Whether
 * that pair currently qualifies is decided by `ExperimentsService`, not here: this only checks the
 * request is well-formed.
 */
export const experimentCreateSchema = z.object({
  pattern_topic: z.string().trim().min(1).max(128),
  pattern_feeling: z.enum(FEELING_KEYS),
  hypothesis_kind: z.enum(['more_of', 'less_of']),
  start_date: dateSchema.optional(),
  length_days: z
    .number()
    .int()
    .min(MIN_EXPERIMENT_LENGTH_DAYS)
    .max(MAX_EXPERIMENT_LENGTH_DAYS)
    .optional(),
});

/** `GET /export?format=` (M-6). Anything else, including a missing value, is a 422. */
export const exportFormatQuerySchema = z.enum(['markdown', 'json']);
