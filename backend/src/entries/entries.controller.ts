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
  Put,
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
  topicFeelingsUpdateSchema,
  versionQuerySchema,
} from '../common/validation';
import type {
  DiaryEntry,
  GuidedAnswer,
  SuggestedFeeling,
  TopicFeelingPairing,
} from '../domain/types';
import { EchoService, type EchoOut } from '../insights/echo.service';
import { ProgressService, type ProgressOut } from '../insights/progress.service';
import { TopicsService, type Topic } from '../topics/topics.service';
import {
  EntriesService,
  EntryNotFoundError,
  InvalidEntryDateError,
  InvalidPairingError,
} from './entries.service';
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
  topicFeelings: TopicFeelingPairing[] = [],
  topics: Topic[] = [],
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
    // L-1b (#35): 'app' for everything written through the normal compose flow, 'daylio_import'
    // for a row the Daylio importer wrote — the visible provenance marker the ticket requires.
    origin: entry.origin,
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
    // E-1a: which of this entry's topics pair with which of its feelings, and whether that pairing
    // is still just a suggestion or something the user has confirmed or overridden. Served on
    // every entry read exactly like `feeling_keys` — a stored fact, not a derived, suppressible
    // proposal the way `suggested_feeling` is. Additive: a client built before this field existed
    // reads every other key exactly as before and simply never looks at this one.
    topic_feelings: topicFeelings.map((pairing) => ({
      topic_id: pairing.topicId,
      topic: pairing.topic,
      feeling_key: pairing.feelingKey,
      source: pairing.source,
    })),
    // #81: the entry's topics on their own, independent of `topic_feelings` above. `topic_feelings`
    // is flattened one row per (topic, feeling) pair, so a topic the engine extracted but could not
    // pair with any feeling — "fine and common" per E-1a — produces no row there at all. This field
    // is sourced from `TopicsService.topicsForEntry()`, the same lookup `echo.service.ts` and
    // `patterns.service.ts` already use, so it always carries every topic linked to the entry,
    // paired or not. Additive, like `topic_feelings`: a client that predates this field reads every
    // other key unchanged and never looks at this one.
    topics: topics.map((topic) => ({ id: topic.id, name: topic.name })),
  };
}

@Controller('entries')
export class EntriesController {
  constructor(
    private readonly entries: EntriesRepository,
    private readonly service: EntriesService,
    private readonly echoes: EchoService,
    private readonly progress: ProgressService,
    private readonly topics: TopicsService,
  ) {}

  /**
   * `createEntry` returns a suggestion synchronously only when inference ran inline (the test
   * double, or a future in-process analyser) — in production `enqueueEntry` only queues the job
   * and `suggestion` is always null here, because the worker is a separate process that has not
   * had a chance to run yet. That null used to be read as "nothing to suggest" and reported as
   * `analysis_pending: false`, which is simply wrong: the job was just queued. Falling back to
   * `analysisFor` reads the real state of that job — pending right after creation, and later
   * whatever the worker actually produced — so a poller has an honest signal to poll on.
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() body: unknown): Record<string, unknown> {
    const input = parseOrThrow(entryCreateSchema, body ?? {});
    try {
      const { entry, suggestion } = this.service.createEntry(input);
      const pairings = this.entries.findTopicFeelingPairings(entry.id);
      const topics = this.topics.topicsForEntry(entry.id);
      if (suggestion) {
        return toEntryOut(entry, suggestion, false, [suggestion], null, pairings, topics);
      }
      const analysis = this.service.analysisFor(entry.id);
      return toEntryOut(
        entry,
        analysis.suggested,
        analysis.pending,
        analysis.suggestedAll,
        null,
        pairings,
        topics,
      );
    } catch (err) {
      if (err instanceof InvalidEntryDateError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
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
            this.entries.findTopicFeelingPairings(updated.id),
            this.topics.topicsForEntry(updated.id),
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

  /**
   * Store the confirmed/overridden pairing set for an entry, replacing whatever was there before
   * (E-1a). `PUT` because this is a full-set overwrite, not an incremental patch — the same
   * semantics `PUT /guided-entry-drafts/{id}/questions/{key}` already uses for a single answer.
   */
  @Put(':entryId/topic-feelings')
  setTopicFeelings(
    @Param('entryId') entryId: string,
    @Body() body: unknown,
  ): Record<string, unknown> {
    const input = parseOrThrow(topicFeelingsUpdateSchema, body ?? {});
    try {
      this.service.setTopicFeelingPairings(
        entryId,
        input.pairings.map((pairing) => ({
          topicId: pairing.topic_id,
          feelingKey: pairing.feeling_key,
        })),
      );
    } catch (err) {
      if (err instanceof EntryNotFoundError) {
        throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
      }
      if (err instanceof InvalidPairingError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
    // The service call above already proved the entry exists (it throws EntryNotFoundError
    // otherwise), so a null here would mean it was deleted in the instant between that write and
    // this read — treated the same as never having existed rather than a crash.
    const entry = this.entries.findById(entryId);
    if (!entry) throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
    const analysis = this.service.analysisFor(entryId);
    return toEntryOut(
      entry,
      analysis.suggested,
      analysis.pending,
      analysis.suggestedAll,
      this.entries.findGuidedAnswers(entryId),
      this.entries.findTopicFeelingPairings(entryId),
      this.topics.topicsForEntry(entryId),
    );
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
          this.entries.findTopicFeelingPairings(e.id),
          this.topics.topicsForEntry(e.id),
        );
      }),
    };
  }

  /**
   * The pattern echo for an entry that has already been saved (I4), plus #37 (L-2)'s near-threshold
   * progress alongside it.
   *
   * Declared before `:entryId` so the two-segment route is matched first, and shaped as a read on
   * a stored entry so there is no version of this request a composer could make about text that is
   * still being written (I4-02). `progress` is additive on the same response rather than a second
   * endpoint: the issue asks for it "alongside the echo response", and the saved screen already
   * calls this one to render the echo panel, so a second round trip would buy nothing a client
   * could not get from this one already returning both.
   */
  @Get(':entryId/echo')
  echo(@Param('entryId') entryId: string): { echoes: EchoOut[]; progress: ProgressOut | null } {
    const entry = this.entries.findById(entryId);
    if (!entry) throw new HttpException('Entry not found', HttpStatus.NOT_FOUND);
    return { echoes: this.echoes.forEntry(entryId), progress: this.progress.forEntry(entryId) };
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
      this.entries.findTopicFeelingPairings(entryId),
      this.topics.topicsForEntry(entryId),
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
