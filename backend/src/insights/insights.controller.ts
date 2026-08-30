import {
  Controller,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { EntitlementsService } from '../billing/entitlements.service';
import { engineConstants, RECENCY_WINDOW_DAYS, type EngineConstants } from './constants';
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
  /**
   * M-3 (#48): tier-independent (see `PatternsService.historySpanDays`'s doc comment) — how many
   * days ago the diary's first entry was written, `null` on an empty diary. Exists so a free
   * account's locked mobile surfaces can state a real fact ("Patterns across your full N months —
   * Premium") instead of inventing one, without revealing any pattern content itself.
   */
  history_span_days: number | null;
}

@Controller('insights')
export class InsightsController {
  constructor(
    private readonly patterns: PatternsService,
    private readonly when: WhenInsightsService,
    private readonly series: SeriesService,
    private readonly entitlements: EntitlementsService,
  ) {}

  /**
   * M-3 (#48): the one place `GET /insights`/`GET /insights/series` decide the free/paid window —
   * `null` for premium ("full ranges", the issue's phrase), `RECENCY_WINDOW_DAYS` for free (the
   * engine's own existing 30-day recency framing, reused rather than a second literal — see
   * `constants.ts`'s doc comment on `EngineConstants.recency_window_days`). `req.userId` is always
   * set by the time a controller runs — `IdentityGate` either attaches it or answers 401 itself
   * before any guard or handler (`../auth/identity.middleware.ts`) — the same guarantee
   * `RequiresPremiumGuard` and `EntitlementsController` already depend on.
   */
  private windowDaysFor(req: Request): number | null {
    const { tier } = this.entitlements.getEntitlement(req.userId as string);
    return tier === 'premium' ? null : RECENCY_WINDOW_DAYS;
  }

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
   *
   * `recomputePatterns` itself is tier-blind on purpose (see `PatternsService.listPatterns`'s doc
   * comment) — it always rebuilds the one full-lifetime pattern set. Only the read after it,
   * `listPatterns`/`contextPatterns`/`engineConstants`, take `windowDaysFor(req)`, so two users
   * with different tiers reading the same diary at the same moment never race each other into
   * writing two different pattern sets.
   */
  @Get()
  async get(@Req() req: Request): Promise<InsightsOut> {
    const userId = req.userId as string;
    const { excludedUnpaired } = await this.patterns.recomputePatterns(userId);
    const windowDays = this.windowDaysFor(req);
    const patterns = this.patterns.listPatterns(userId, windowDays);
    const withdrawals = this.patterns.listWithdrawals(userId);
    return {
      patterns,
      // A2-03/A2-09: a withdrawal is computed, so it ships whatever else is unfinished. It is
      // returned beside the patterns rather than behind a second request precisely so a client
      // cannot render Insights without it.
      withdrawals,
      new_withdrawal_count: withdrawals.filter((withdrawal) => withdrawal.is_new).length,
      // The client branches on this flag, not on array length.
      insufficient_data: patterns.length === 0,
      constants: engineConstants(windowDays),
      // #21: computed fresh on every read, same as `patterns` — but never persisted, so there is no
      // recompute step for it to depend on. Ordering after `recomputePatterns()` regardless, so a
      // request that also just wrote entries sees the same up-to-date `diary_entries` rows.
      context_patterns: this.patterns.contextPatterns(userId, windowDays),
      excluded_unpaired: excludedUnpaired,
      history_span_days: this.patterns.historySpanDays(userId),
    };
  }

  /** I5. Served separately because it answers a different question and costs a different query. */
  @Get('when')
  getWhen(@Req() req: Request): WhenInsights {
    return this.when.get(req.userId as string);
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
    @Req() req: Request,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('granularity') granularity?: string,
  ): SeriesOut {
    if (!from) throw new HttpException('Field required: from', HttpStatus.UNPROCESSABLE_ENTITY);
    if (!to) throw new HttpException('Field required: to', HttpStatus.UNPROCESSABLE_ENTITY);
    const parsedGranularity = parseGranularity(granularity);
    // M-3 (#48): a separate mechanism from `GET /insights`'s window, per the issue — that one
    // excludes historical rows from an unbounded read; this one rejects a caller-chosen range that
    // reaches too far back, the same shape `MAX_SERIES_RANGE_DAYS` below already uses for the
    // day-granularity ceiling. Free reuses `RECENCY_WINDOW_DAYS` (the same 30 as the patterns
    // window) rather than a second literal; premium passes `null`, "full ranges" per the issue.
    try {
      return this.series.getSeries(
        req.userId as string,
        from,
        to,
        parsedGranularity,
        this.windowDaysFor(req),
      );
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
  acknowledge(@Req() req: Request): void {
    this.patterns.acknowledgeWithdrawals(req.userId as string);
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
