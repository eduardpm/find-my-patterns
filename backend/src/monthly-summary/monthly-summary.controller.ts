import { Controller, Get, HttpException, HttpStatus, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import {
  InvalidMonthError,
  MonthlySummaryService,
  type MonthlySummary,
} from './monthly-summary.service';

@Controller('monthly-summary')
export class MonthlySummaryController {
  constructor(private readonly summaries: MonthlySummaryService) {}

  @Get()
  get(@Query('month') month: string | undefined, @Req() req: Request): MonthlySummary {
    if (!month) {
      throw new HttpException('Field required: month', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    try {
      return this.summaries.get(req.userId as string, month);
    } catch (err) {
      if (err instanceof InvalidMonthError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
  }
}
