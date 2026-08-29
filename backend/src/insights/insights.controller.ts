import { Controller, Get, HttpCode, HttpException, HttpStatus, Post, Query } from '@nestjs/common';
import { engineConstants, type EngineConstants } from './constants';
import {
  PatternsService,
  type ContextPatternOut,
  type PatternOut,
  type WithdrawalOut,
} from './patterns.service';
import {
  InvalidSeriesRangeError,
  SeriesService,
  type SeriesGranularity,
  type SeriesOut,
} from './series.service';
import { WhenInsightsService, type WhenInsights } from './when.service';

export interface InsightsOut {
  patterns: PatternOut[];
  withdrawals: WithdrawalOut[];
  new_withdrawal_count: number;
  insufficient_data: boolean;
  constants: EngineConstants;
  /**
   * #21: passive weekday/day-type/time-of-day/season patterns, in their own array so an existing
   * client — this API predates it and both `web/` and `mobile/` decode this payload — reads exactly
   * the fields it already knew about and silently ignores this one until its own UI ticket lands.
   * `insufficient_data` is unaffected by this array on purpose: it is still computed from `patterns`
   * alone, the same as before #21 (a diary with only context patterns and no topic ones was already
   * "not enough topic evidence" before this array existed, and stays that way).
   */
  context_patterns: ContextPatternOut[];
  /**
   * E-1b acceptance criterion 5: how many in-window entries are mixed-valence and never went
   * through the pairing step at all — zero rows in `entry_topic_feelings`, not merely "confirmed
   * some pairs and left a cross combination unlinked". That distinction is deliberate: an entry
   * that confirmed (topic, feelingA) and (otherTopic, feelingB) has permanently and intentionally
   * excluded (topic, feelingB) — pairing it further changes nothing, so counting it here would be
   * false transparency. Only an entry with *no* confirmed pairing at all is one where confirming
   * anything would move it from counting toward nothing to counting toward whatever it confirms,
   * which is the literal claim the eventual UI notice ("n entries not counted until you pair
   * them") makes. Additive and top-level (not per-pattern, and not per-entry) — see
   * `PatternsService#buildCandidates` for the full reasoning. Zero on every diary with no
   * mixed-valence, never-paired entries, which is the common case rule 1 leaves untouched.
   */
  excluded_unpaired: number;
}

@Controller('insights')
export class InsightsController {
  constructor(
    private readonly patterns: PatternsService,
    private readonly when: WhenInsightsService,
    private readonly series: SeriesService,
  ) {}

  /**
   * Recomputes before reading.
   *
   * This endpoint **writes** — `recomputePatterns()` rewrites `pattern_entries` on every call. That
   * is current behaviour, faithfully preserved, and it is why SC-011's "reading every screen leaves
   * the data unchanged" cannot be met literally without breaking SC-002. See the note at the top of
   * tasks.md and T072.
   *
   * Recomputation is also the *only* place the engine runs (C-06). Saving an entry never pays for
   * it, and no client ever computes a number this response carries (C-01).
   */
  @Get()
  async get(): Promise<InsightsOut> {
    const { excludedUnpaired } = await this.patterns.recomputePatterns();
    const patterns = this.patterns.listPatterns();
    const withdrawals = this.patterns.listWithdrawals();
    return {
      patterns,
      // A2-03/A2-09: a withdrawal is computed, so it ships whatever else is unfinished. It is
      // returned beside the patterns rather than behind a second request precisely so a client
      // cannot render Insights without it.
      withdrawals,
      new_withdrawal_count: withdrawals.filter((withdrawal) => withdrawal.is_new).length,
      // The client branches on this flag, not on array length.
      insufficient_data: patterns.length === 0,
      constants: engineConstants(),
      // #21: computed fresh on every read, same as `patterns` — but never persisted, so there is no
      // recompute step for it to depend on. Ordering after `recomputePatterns()` regardless, so a
      // request that also just wrote entries sees the same up-to-date `diary_entries` rows.
      context_patterns: this.patterns.contextPatterns(),
      excluded_unpaired: excludedUnpaired,
    };
  }

  /** I5. Served separately because it answers a different question and costs a different query. */
  @Get('when')
  getWhen(): WhenInsights {
    return this.when.get();
  }

  /**
   * CH-0: the shared prerequisite behind every chart (mood line, Year in Pixels, the topic
   * sparkline, Year in Review) — a day score plus a range read, so no client computes one for
   * itself. `granularity` defaults to `day`; `week` and `month` aggregate by the mean of day
   * scores, not by pooling feelings (see `constants.ts` for why).
   *
   * A pure read — unlike `GET /insights`, nothing here recomputes anything.
   *
   * `topic_id` filtering and an intensity-weighted variant are deliberately out of scope for this
   * endpoint; see the day-score doc in `constants.ts`.
   */
  @Get('series')
  getSeries(
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('granularity') granularity?: string,
  ): SeriesOut {
    if (!from) throw new HttpException('Field required: from', HttpStatus.UNPROCESSABLE_ENTITY);
    if (!to) throw new HttpException('Field required: to', HttpStatus.UNPROCESSABLE_ENTITY);
    const parsedGranularity = parseGranularity(granularity);
    try {
      return this.series.getSeries(from, to, parsedGranularity);
    } catch (err) {
      if (err instanceof InvalidSeriesRangeError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
  }

  /**
   * A2-07: the user has seen the current withdrawal notices.
   *
   * An explicit action rather than a side effect of the GET — see `acknowledgeWithdrawals`.
   */
  @Post('withdrawals/acknowledge')
  @HttpCode(HttpStatus.NO_CONTENT)
  acknowledge(): void {
    this.patterns.acknowledgeWithdrawals();
  }
}

/** `day` is the documented default; anything other than the three named values is a 422, not a 500. */
function parseGranularity(value: string | undefined): SeriesGranularity {
  if (value === undefined) return 'day';
  if (value === 'day' || value === 'week' || value === 'month') return value;
  throw new HttpException(
    `Invalid granularity: '${value}', expected day, week or month`,
    HttpStatus.UNPROCESSABLE_ENTITY,
  );
}
