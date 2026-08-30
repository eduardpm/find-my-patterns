import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Post,
  Put,
  Query,
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { guidedDraftAnswerSchema, orderIndexQuerySchema, parseOrThrow } from '../common/validation';
import { TranscriptionJobsService } from '../transcription/transcription-jobs.service';
import { TopicsService } from '../topics/topics.service';
import { toEntryOut } from './entries.controller';
import { EntriesRepository } from './entries.repository';
import { EmptyGuidedDraftError, EntriesService, GuidedDraftNotFoundError } from './entries.service';

@Controller('guided-entry-drafts')
export class GuidedDraftsController {
  constructor(
    private readonly entries: EntriesService,
    private readonly entriesRepo: EntriesRepository,
    private readonly transcriptionJobs: TranscriptionJobsService,
    private readonly topics: TopicsService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Req() request: Request): { draft_key: string } {
    return { draft_key: this.entries.createGuidedDraft(request.userId as string) };
  }

  @Get(':draftKey')
  get(@Param('draftKey') draftKey: string, @Req() request: Request): { answers: unknown[] } {
    try {
      return this.entries.getGuidedDraft(request.userId as string, draftKey);
    } catch (error) {
      this.rethrowDraftError(error);
    }
  }

  @Put(':draftKey/questions/:questionKey')
  @HttpCode(HttpStatus.NO_CONTENT)
  saveAnswer(
    @Param('draftKey') draftKey: string,
    @Param('questionKey') questionKey: string,
    @Body() body: unknown,
    @Req() request: Request,
  ): void {
    const answer = parseOrThrow(guidedDraftAnswerSchema, body ?? {});
    try {
      this.entries.saveGuidedDraftAnswer(
        request.userId as string,
        draftKey,
        questionKey,
        answer.answer_text,
        answer.order_index,
      );
    } catch (error) {
      this.rethrowDraftError(error);
    }
  }

  @Post(':draftKey/questions/:questionKey/transcriptions')
  @HttpCode(HttpStatus.ACCEPTED)
  transcribeAnswer(
    @Param('draftKey') draftKey: string,
    @Param('questionKey') questionKey: string,
    @Query('order') order: string | undefined,
    @Req() request: Request,
  ): { id: string; status: 'pending' } {
    const userId = request.userId as string;
    const contentType = request.get('content-type')?.split(';', 1)[0].trim().toLowerCase() ?? '';
    if (!contentType.startsWith('audio/')) {
      throw new HttpException(
        'An audio content type is required.',
        HttpStatus.UNSUPPORTED_MEDIA_TYPE,
      );
    }
    if (!Buffer.isBuffer(request.body) || request.body.length === 0) {
      throw new HttpException('The recording is empty.', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    if (order === undefined) {
      throw new HttpException('Field required: order', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    const orderIndex = parseOrThrow(orderIndexQuerySchema, order);
    try {
      this.entries.getGuidedDraft(userId, draftKey);
      return {
        id: this.transcriptionJobs.start(userId, request.body, {
          entryId: draftKey,
          questionKey,
          orderIndex,
        }),
        status: 'pending',
      };
    } catch (error) {
      this.rethrowDraftError(error);
    }
  }

  /**
   * See `EntriesController.create`'s doc comment for why `suggestion` being null does not mean
   * "nothing to suggest": in production it means the job was just queued, and `analysisFor` is
   * what reports that honestly instead of a hardcoded `analysis_pending: false`.
   */
  @Post(':draftKey/finalize')
  finalize(@Param('draftKey') draftKey: string, @Req() request: Request): Record<string, unknown> {
    const userId = request.userId as string;
    try {
      const { entry, suggestion } = this.entries.finalizeGuidedDraft(userId, draftKey);
      const pairings = this.entriesRepo.findTopicFeelingPairings(userId, entry.id);
      const topics = this.topics.topicsForEntry(userId, entry.id);
      if (suggestion) return toEntryOut(entry, suggestion, false, [], null, pairings, topics);
      const analysis = this.entries.analysisFor(userId, entry.id);
      return toEntryOut(
        entry,
        analysis.suggested,
        analysis.pending,
        analysis.suggestedAll,
        null,
        pairings,
        topics,
      );
    } catch (error) {
      if (error instanceof EmptyGuidedDraftError) {
        throw new HttpException('The draft has no answers.', HttpStatus.UNPROCESSABLE_ENTITY);
      }
      this.rethrowDraftError(error);
    }
  }

  @Delete(':draftKey')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('draftKey') draftKey: string, @Req() request: Request): void {
    try {
      this.entries.deleteGuidedDraft(request.userId as string, draftKey);
    } catch (error) {
      this.rethrowDraftError(error);
    }
  }

  private rethrowDraftError(error: unknown): never {
    if (error instanceof GuidedDraftNotFoundError) {
      throw new HttpException('Guided entry draft not found.', HttpStatus.NOT_FOUND);
    }
    throw error;
  }
}
