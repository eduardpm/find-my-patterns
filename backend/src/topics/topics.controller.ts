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
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { parseOrThrow, topicAliasSchema } from '../common/validation';
import {
  InvalidAliasError,
  TopicNotFoundError,
  TopicsService,
  type TopicDetail,
} from './topics.service';

/**
 * The alias table, as something the user can edit (A4-04).
 *
 * This is the half of topic normalisation the backend cannot decide on its own. "gym session" is
 * exercise in most people's diaries and something else entirely in a physiotherapist's; the rules
 * in `canonicalization.ts` handle the cases that are true for everyone, and this endpoint handles
 * the rest without the model being asked to guess (A4-03).
 *
 * Edits take effect on the next recompute, because `recomputePatterns` re-runs consolidation on
 * every read. Nothing here re-runs the model.
 */
@Controller('topics')
export class TopicsController {
  constructor(private readonly topics: TopicsService) {}

  @Get()
  list(@Req() req: Request): { topics: TopicDetail[] } {
    return { topics: this.topics.listTopics(req.userId as string) };
  }

  @Post(':topicId/aliases')
  @HttpCode(HttpStatus.OK)
  add(@Param('topicId') topicId: string, @Body() body: unknown, @Req() req: Request): TopicDetail {
    const input = parseOrThrow(topicAliasSchema, body ?? {});
    try {
      return this.topics.addAlias(req.userId as string, topicId, input.alias);
    } catch (err) {
      throw translate(err);
    }
  }

  @Delete(':topicId/aliases/:alias')
  remove(
    @Param('topicId') topicId: string,
    @Param('alias') alias: string,
    @Req() req: Request,
  ): TopicDetail {
    try {
      return this.topics.removeAlias(req.userId as string, topicId, decodeURIComponent(alias));
    } catch (err) {
      throw translate(err);
    }
  }
}

function translate(err: unknown): unknown {
  if (err instanceof TopicNotFoundError) {
    return new HttpException('Topic not found', HttpStatus.NOT_FOUND);
  }
  // 422 rather than 400 for the same reason every other invalid field in this API answers 422:
  // the request was understood, the value was not acceptable (contracts/api.md).
  if (err instanceof InvalidAliasError) {
    return new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
  }
  return err;
}
