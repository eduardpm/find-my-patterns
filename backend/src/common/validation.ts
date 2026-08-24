import { HttpException, HttpStatus } from '@nestjs/common';
import { z, type ZodType } from 'zod';
import { FEELING_KEYS } from '../inference/inference';

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

/** `version` is required — without it there is no way to tell a deliberate edit from a stale one. */
export const entryUpdateSchema = z.object({
  raw_text: z.string().nullish(),
  feeling_key: z.enum(FEELING_KEYS).nullish(),
  version: z.number().int(),
});

export const versionQuerySchema = z.coerce.number().int();

export const guidedDraftAnswerSchema = z.object({
  answer_text: z.string().trim().min(1),
  order_index: z.number().int().min(0).max(100),
});

export const orderIndexQuerySchema = z.coerce.number().int().min(0).max(100);
