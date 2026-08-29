import { Controller, Get, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { engineConstants, type EngineConstants } from './constants';
import { PatternsService, type PatternOut, type WithdrawalOut } from './patterns.service';
import { WhenInsightsService, type WhenInsights } from './when.service';

export interface InsightsOut {
  patterns: PatternOut[];
  withdrawals: WithdrawalOut[];
  new_withdrawal_count: number;
  insufficient_data: boolean;
  constants: EngineConstants;
}

@Controller('insights')
export class InsightsController {
  constructor(
    private readonly patterns: PatternsService,
    private readonly when: WhenInsightsService,
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
    await this.patterns.recomputePatterns();
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
    };
  }

  /** I5. Served separately because it answers a different question and costs a different query. */
  @Get('when')
  getWhen(): WhenInsights {
    return this.when.get();
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
