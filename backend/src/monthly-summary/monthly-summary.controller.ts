import { Controller, Get, HttpException, HttpStatus, Query } from '@nestjs/common';
import {
  InvalidMonthError,
  MonthlySummaryService,
  type MonthlySummary,
} from './monthly-summary.service';

@Controller('monthly-summary')
export class MonthlySummaryController {
  constructor(private readonly summaries: MonthlySummaryService) {}

  @Get()
  get(@Query('month') month?: string): MonthlySummary {
    if (!month) {
      throw new HttpException('Field required: month', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    try {
      return this.summaries.get(month);
    } catch (err) {
      if (err instanceof InvalidMonthError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
  }
}
