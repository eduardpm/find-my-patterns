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
import type { DiaryEntry, GuidedAnswer, SuggestedFeeling } from '../domain/types';
import { EchoService, type EchoOut } from '../insights/echo.service';
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
  analysisPending = false,
  suggestedAll: SuggestedFeeling[] = [],
  guidedAnswers: GuidedAnswer[] | null = null,
): Record<string, unknown> {
  return {
    id: entry.id,
    created_at: serializeDateTime(entry.createdAt),
    entry_date: serializeDate(entry.entryDate),
    mode: entry.mode,
    raw_text: entry.rawText,
    // `feeling_key`/`suggested_feeling` are the primary feeling and stay in the payload beside the
    // full lists. They are what a client built before the vocabulary grew reads, and they are
    // still what the calendar dot and the entry rail are keyed on.
    feeling_key: entry.feelingKey,
    feeling_keys: entry.feelingKeys,
    feeling_source: entry.feelingSource,
    // I6-04: served to both clients, so entry detail and the calendar cell can show how strongly
    // the feeling was felt rather than only which feeling it was.
    feeling_intensity: entry.feelingIntensity,
    // One rating per feeling, keyed by feeling key, holding only the feelings the user actually
    // rated. `feeling_intensity` above is this map read at `feeling_key` and stays in the payload
    // for the calendar cell and for clients built before the dial moved off the entry.
    feeling_intensities: entry.feelingIntensities,
    suggested_feeling: suggestion,
    suggested_feelings: suggestedAll,
    analysis_pending: analysisPending,
    version: entry.version,
    // The questions this entry was written against, with the wording they were answered under.
    // Present so a client can lay a guided entry out as the questions and answers it actually is,
    // rather than re-deriving that from the run-together prose in `raw_text` — which it cannot do,
    // because a user is free to edit that text afterwards. `null` means "not loaded on this
    // endpoint"; `[]` means the entry has none, which is every freeform entry.
    guided_answers:
      guidedAnswers === null
        ? null
        : guidedAnswers.map((answer) => ({
            question_key: answer.questionKey,
            question_text: answer.questionTextSnapshot,
            answer_text: answer.answerText,
            order_index: answer.orderIndex,
          })),
  };
}

@Controller('entries')
export class EntriesController {
  constructor(
    private readonly entries: EntriesRepository,
    private readonly service: EntriesService,
    private readonly echoes: EchoService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() body: unknown): Record<string, unknown> {
    const input = parseOrThrow(entryCreateSchema, body ?? {});
    const { entry, suggestion } = this.service.createEntry(input);
    return toEntryOut(entry, suggestion, false, suggestion ? [suggestion] : []);
  }

  @Patch(':entryId')
  update(@Param('entryId') entryId: string, @Body() body: unknown, @Res() res: Response): void {
    const input = parseOrThrow(entryUpdateSchema, body ?? {});
    try {
      const updated = this.service.updateEntry(entryId, input);
      const analysis = this.service.analysisFor(entryId);
      res
        .status(HttpStatus.OK)
        .json(
          toEntryOut(
            updated,
            analysis.suggested,
            analysis.pending,
            analysis.suggestedAll,
            this.entries.findGuidedAnswers(updated.id),
          ),
        );
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
    return {
      entries: this.entries.findByDate(parsed).map((e) => {
        const analysis = this.service.analysisFor(e.id);
        // Answers are served with the list because this is the endpoint a client opens an entry
        // from — there is no separate per-entry read on the way to the detail screen, so leaving
        // them out here would mean showing the entry before it can be laid out properly.
        return toEntryOut(
          e,
          analysis.suggested,
          analysis.pending,
          analysis.suggestedAll,
          this.entries.findGuidedAnswers(e.id),
        );
      }),
    };
  }

  /**
   * The pattern echo for an entry that has already been saved (I4).
   *
   * Declared before `:entryId` so the two-segment route is matched first, and shaped as a read on
   * a stored entry so there is no version of this request a composer could make about text that is
   * still being written (I4-02).
   */
  @Get(':entryId/echo')
  echo(@Param('entryId') entryId: string): { echoes: EchoOut[] } {
    const entry = this.entries.findById(entryId);
    if (!entry) throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
    return { echoes: this.echoes.forEntry(entryId) };
  }

  @Get(':entryId')
  getOne(@Param('entryId') entryId: string): Record<string, unknown> {
    const entry = this.entries.findById(entryId);
    if (!entry) throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
    const analysis = this.service.analysisFor(entryId);
    return toEntryOut(
      entry,
      analysis.suggested,
      analysis.pending,
      analysis.suggestedAll,
      this.entries.findGuidedAnswers(entryId),
    );
  }
}

interface FeelingOut {
  key: string;
  label: string;
  valence: string;
  group_key: string;
}

interface FeelingGroupOut {
  key: string;
  label: string;
  valence: string;
  feelings: FeelingOut[];
}

@Controller('feelings')
export class FeelingsController {
  constructor(private readonly feelings: FeelingsRepository) {}

  /**
   * The vocabulary, served twice over: nested as `groups`, and flat as `feelings`.
   *
   * The duplication is deliberate and cheap. `groups` is what both clients render — a short row of
   * group chips that open onto that group's feelings — and `feelings` is what they index a stored
   * `feeling_key` against when showing an entry, which is a lookup, not a menu. Serving only the
   * nested shape would make every client flatten it for itself, which is a rule leaking into the
   * clients; serving only the flat one would make every client rebuild the grouping.
   *
   * Emoji and accent colours are deliberately absent — presentation belongs to each client
   * (Principle VII).
   */
  @Get()
  list(): { groups: FeelingGroupOut[]; feelings: FeelingOut[] } {
    return {
      groups: this.feelings.findGroups().map((group) => ({
        key: group.key,
        label: group.label,
        valence: group.valence,
        feelings: group.feelings.map(toFeelingOut),
      })),
      feelings: this.feelings.findAll().map(toFeelingOut),
    };
  }
}

function toFeelingOut(feeling: {
  key: string;
  label: string;
  valence: string;
  groupKey: string;
}): FeelingOut {
  return {
    key: feeling.key,
    label: feeling.label,
    valence: feeling.valence,
    group_key: feeling.groupKey,
  };
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
