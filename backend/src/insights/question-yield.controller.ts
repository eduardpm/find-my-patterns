import { Controller, Get, HttpException, HttpStatus, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { decodeDate } from '../db/codecs';
import { QuestionYieldService, type QuestionYieldReport } from './question-yield.service';

/**
 * L-4 / SC-008: `GET /insights/question-yield`.
 *
 * A separate controller rather than another handler on `InsightsController` — a neighbouring
 * ticket is adding `GET /insights/series` to that controller at the same time, and this endpoint
 * has no state or dependency in common with it. NestJS controllers accept a full path, so the
 * route stays exactly `/insights/question-yield` either way.
 */
@Controller('insights/question-yield')
export class QuestionYieldController {
  constructor(private readonly service: QuestionYieldService) {}

  @Get()
  get(
    @Query('from') from: string | undefined,
    @Query('to') to: string | undefined,
    @Req() req: Request,
  ): QuestionYieldReport {
    if (from !== undefined) assertDateFormat('from', from);
    if (to !== undefined) assertDateFormat('to', to);
    if (from !== undefined && to !== undefined && from > to) {
      throw new HttpException(
        `'from' (${from}) must not be after 'to' (${to})`,
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    return this.service.compute(req.userId as string, { from, to });
  }
}

/** Same validation `GET /entries?date=` uses: `decodeDate` for shape, 422 rather than 400. */
function assertDateFormat(field: string, value: string): void {
  try {
    decodeDate(value);
  } catch {
    throw new HttpException(
      `Invalid ${field}, expected format YYYY-MM-DD`,
      HttpStatus.UNPROCESSABLE_ENTITY,
    );
  }
}
