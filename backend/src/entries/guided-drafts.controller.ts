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
import { toEntryOut } from './entries.controller';
import { EmptyGuidedDraftError, EntriesService, GuidedDraftNotFoundError } from './entries.service';

@Controller('guided-entry-drafts')
export class GuidedDraftsController {
  constructor(
    private readonly entries: EntriesService,
    private readonly transcriptionJobs: TranscriptionJobsService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(): { draft_key: string } {
    return { draft_key: this.entries.createGuidedDraft() };
  }

  @Get(':draftKey')
  get(@Param('draftKey') draftKey: string): { answers: unknown[] } {
    try {
      return this.entries.getGuidedDraft(draftKey);
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
  ): void {
    const answer = parseOrThrow(guidedDraftAnswerSchema, body ?? {});
    try {
      this.entries.saveGuidedDraftAnswer(
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
      this.entries.getGuidedDraft(draftKey);
      return {
        id: this.transcriptionJobs.start(request.body, {
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

  @Post(':draftKey/finalize')
  finalize(@Param('draftKey') draftKey: string): Record<string, unknown> {
    try {
      const { entry, suggestion } = this.entries.finalizeGuidedDraft(draftKey);
      return toEntryOut(entry, suggestion);
    } catch (error) {
      if (error instanceof EmptyGuidedDraftError) {
        throw new HttpException('The draft has no answers.', HttpStatus.UNPROCESSABLE_ENTITY);
      }
      this.rethrowDraftError(error);
    }
  }

  @Delete(':draftKey')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('draftKey') draftKey: string): void {
    try {
      this.entries.deleteGuidedDraft(draftKey);
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
