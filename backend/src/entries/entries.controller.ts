import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import { decodeDate, serializeDate, serializeDateTime } from '../db/codecs';
import { StaleEntryError, staleEntryBody } from '../common/stale-entry';
import {
  entryCreateSchema,
  entryUpdateSchema,
  parseOrThrow,
  versionQuerySchema,
} from '../common/validation';
import type { DiaryEntry, SuggestedFeeling } from '../domain/types';
import { EntriesService, EntryNotFoundError } from './entries.service';
import {
  EntriesRepository,
  FeelingsRepository,
  GuidingQuestionsRepository,
} from './entries.repository';

/**
 * Wire shape for an entry. Every key is always present — `feeling_key` and `suggested_feeling` are
 * emitted as `null` rather than omitted, because the Android client parses this with a
 * statically-typed serializer and a missing key is a different thing from a null one.
 */
export function toEntryOut(
  entry: DiaryEntry,
  suggestion: SuggestedFeeling | null = null,
): Record<string, unknown> {
  return {
    id: entry.id,
    created_at: serializeDateTime(entry.createdAt),
    entry_date: serializeDate(entry.entryDate),
    mode: entry.mode,
    raw_text: entry.rawText,
    feeling_key: entry.feelingKey,
    feeling_source: entry.feelingSource,
    suggested_feeling: suggestion,
    version: entry.version,
  };
}

@Controller('entries')
export class EntriesController {
  constructor(
    private readonly entries: EntriesRepository,
    private readonly service: EntriesService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() body: unknown): Record<string, unknown> {
    const input = parseOrThrow(entryCreateSchema, body ?? {});
    const { entry, suggestion } = this.service.createEntry(input);
    return toEntryOut(entry, suggestion);
  }

  @Patch(':entryId')
  update(@Param('entryId') entryId: string, @Body() body: unknown, @Res() res: Response): void {
    const input = parseOrThrow(entryUpdateSchema, body ?? {});
    try {
      res.status(HttpStatus.OK).json(toEntryOut(this.service.updateEntry(entryId, input)));
    } catch (err) {
      if (err instanceof EntryNotFoundError) {
        throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
      }
      if (err instanceof StaleEntryError) {
        // Returned directly, never thrown: the global filter would strip the `current` sibling
        // and relabel the code (contracts/api.md).
        res.status(HttpStatus.CONFLICT).json(staleEntryBody(toEntryOut(err.current)));
        return;
      }
      throw err;
    }
  }

  @Delete(':entryId')
  remove(
    @Param('entryId') entryId: string,
    @Query('version') version: string | undefined,
    @Res() res: Response,
  ): void {
    if (version === undefined) {
      throw new HttpException('Field required: version', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    const parsed = parseOrThrow(versionQuerySchema, version);
    try {
      this.service.deleteEntry(entryId, parsed);
      res.status(HttpStatus.NO_CONTENT).send();
    } catch (err) {
      if (err instanceof EntryNotFoundError) {
        throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
      }
      if (err instanceof StaleEntryError) {
        res.status(HttpStatus.CONFLICT).json(staleEntryBody(toEntryOut(err.current)));
        return;
      }
      throw err;
    }
  }

  @Get()
  list(@Query('date') date?: string): { entries: Record<string, unknown>[] } {
    if (!date) {
      throw new HttpException('Field required: date', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    let parsed;
    try {
      parsed = decodeDate(date);
    } catch {
      throw new HttpException(
        'Invalid date, expected format YYYY-MM-DD',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    return { entries: this.entries.findByDate(parsed).map((e) => toEntryOut(e)) };
  }

  @Get(':entryId')
  getOne(@Param('entryId') entryId: string): Record<string, unknown> {
    const entry = this.entries.findById(entryId);
    if (!entry) throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
    return toEntryOut(entry);
  }
}

@Controller('feelings')
export class FeelingsController {
  constructor(private readonly feelings: FeelingsRepository) {}

  @Get()
  list(): { feelings: Array<{ key: string; label: string; valence: string }> } {
    // Emoji are deliberately absent — presentation belongs to each client (Principle VII).
    return { feelings: this.feelings.findAll() };
  }
}

@Controller('guiding-questions')
export class GuidingQuestionsController {
  constructor(private readonly questions: GuidingQuestionsRepository) {}

  @Get()
  list(): { questions: Record<string, unknown>[] } {
    return {
      questions: this.questions.findAll().map((q) => ({
        key: q.key,
        category: q.category,
        prompt_text: q.promptText,
        trigger_keywords: q.triggerKeywords,
        is_mandatory: q.isMandatory,
      })),
    };
  }
}
