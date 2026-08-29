import { Controller, Get, HttpException, HttpStatus, Query, Res } from '@nestjs/common';
import type { Response } from 'express';
import { serializeDate, todayLocal } from '../db/codecs';
import { exportFormatQuerySchema, parseOrThrow } from '../common/validation';
import { ExportService } from './export.service';

/**
 * `GET /export?format=markdown|json` — the whole diary, in one response (M-6).
 *
 * No pagination and no windowing: every other read endpoint in this API answers a slice (a day, a
 * month, one entry) because that is what a screen needs, but this one exists precisely so a person
 * can walk away with everything they wrote, so there is no parameter that could leave part of it
 * behind.
 */
@Controller('export')
export class ExportController {
  constructor(private readonly exportService: ExportService) {}

  @Get()
  get(@Query('format') format: string | undefined, @Res() res: Response): void {
    if (!format) {
      throw new HttpException('Field required: format', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    const parsed = parseOrThrow(exportFormatQuerySchema, format);
    // Today's date, not the diary's date range — this only names the file a browser or share
    // sheet offers to save, the same role a backup's filename plays in `npm run backup`.
    const filenameDate = serializeDate(todayLocal());

    if (parsed === 'json') {
      const body = JSON.stringify(this.exportService.toJson(), null, 2);
      res
        .status(HttpStatus.OK)
        .set({
          'Content-Type': 'application/json; charset=utf-8',
          'Content-Disposition': `attachment; filename="find-my-patterns-export-${filenameDate}.json"`,
        })
        .send(body);
      return;
    }

    const body = this.exportService.toMarkdown();
    res
      .status(HttpStatus.OK)
      .set({
        'Content-Type': 'text/markdown; charset=utf-8',
        'Content-Disposition': `attachment; filename="find-my-patterns-export-${filenameDate}.md"`,
      })
      .send(body);
  }
}
