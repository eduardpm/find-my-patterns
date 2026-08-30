import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Post,
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { decodeDate } from '../db/codecs';
import { experimentCreateSchema, parseOrThrow } from '../common/validation';
import { RequiresPremium } from '../billing/requires-premium.guard';
import {
  ActiveExperimentExistsError,
  ExperimentNotActiveError,
  ExperimentNotFoundError,
  ExperimentsService,
  InvalidExperimentLengthError,
  NoActiveExperimentError,
  NonQualifyingPatternError,
  type ExperimentOut,
  type ExperimentResultsOut,
} from './experiments.service';

/**
 * N-of-1 experiments (R-3a). Backend half only — the client that starts an experiment from a
 * pattern card, shows the "experiment active" banner, and renders the results view is R-3b.
 *
 * Every failure here answers **422 `validation_error`**, never 400 (contracts/api.md): a
 * malformed body, an out-of-range length, a non-qualifying pattern and an already-active
 * experiment are all "the request was understood, the value was not acceptable" — the same reason
 * every other invalid field in this API answers 422.
 *
 * M-3 (#48): only **creating** an experiment is gated. `GET /active`, `GET /:id/results` and
 * `POST /:id/abandon` all stay reachable regardless of tier — the product rule this ticket applies
 * everywhere is "never paywall reading back", and the two GETs are exactly that: a lapsed premium
 * user must still be able to see the experiment they already started and read the results it
 * already produced, the same as they can still read every diary entry they wrote while premium.
 * `abandon` is deliberately ungated too, for a related but distinct reason — it is the only way to
 * clear a stuck `active` experiment (`ActiveExperimentExistsError` below blocks a second `create`
 * while one exists), so gating it would trap a lapsed user who started an experiment while premium
 * behind a wall they can no longer pay through to get past: they could neither finish it nor
 * abandon it to start fresh once premium again. Gating stops them from *starting* new premium
 * value, which `create` alone already does.
 */
@Controller('experiments')
export class ExperimentsController {
  constructor(private readonly experiments: ExperimentsService) {}

  @Post()
  @RequiresPremium()
  async create(@Body() body: unknown, @Req() req: Request): Promise<ExperimentOut> {
    const input = parseOrThrow(experimentCreateSchema, body ?? {});
    // `experimentCreateSchema` only checks `start_date`'s shape (`YYYY-MM-DD`); a value that is
    // the right shape but not a real calendar date (`2026-02-30`) is caught here, before the
    // service sees it, so it still answers 422 rather than the generic 500 an unrecognised date
    // would otherwise throw from deep inside `decodeDate`.
    let startDate;
    try {
      startDate = input.start_date ? decodeDate(input.start_date) : undefined;
    } catch (err) {
      throw new HttpException(
        err instanceof Error ? err.message : 'Invalid start_date',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    try {
      return await this.experiments.create(req.userId as string, {
        patternTopic: input.pattern_topic,
        patternFeeling: input.pattern_feeling,
        hypothesisKind: input.hypothesis_kind,
        startDate,
        lengthDays: input.length_days,
      });
    } catch (err) {
      throw translate(err);
    }
  }

  @Get('active')
  getActive(@Req() req: Request): ExperimentOut {
    try {
      return this.experiments.getActive(req.userId as string);
    } catch (err) {
      throw translate(err);
    }
  }

  @Post(':id/abandon')
  @HttpCode(HttpStatus.OK)
  abandon(@Param('id') id: string, @Req() req: Request): ExperimentOut {
    try {
      return this.experiments.abandon(req.userId as string, id);
    } catch (err) {
      throw translate(err);
    }
  }

  @Get(':id/results')
  results(@Param('id') id: string, @Req() req: Request): ExperimentResultsOut {
    try {
      return this.experiments.results(req.userId as string, id);
    } catch (err) {
      throw translate(err);
    }
  }
}

function translate(err: unknown): unknown {
  if (err instanceof ExperimentNotFoundError || err instanceof NoActiveExperimentError) {
    return new HttpException(err.message, HttpStatus.NOT_FOUND);
  }
  if (
    err instanceof ActiveExperimentExistsError ||
    err instanceof NonQualifyingPatternError ||
    err instanceof ExperimentNotActiveError ||
    err instanceof InvalidExperimentLengthError
  ) {
    return new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
  }
  return err;
}
