import { Controller, Get, HttpException, HttpStatus, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequiresPremium } from '../billing/requires-premium.guard';
import { DigestService, InvalidDigestWeekError, type DigestResponse } from './digest.service';

/**
 * [R-2] `GET /insights/digest` — its own controller, not a third method on `InsightsController`
 * (the orchestrator's own instruction): `#37` lands a new insights service in this same directory
 * at the same time, and a shared controller file would be the one place the two changes could not
 * both land as plain text.
 *
 * A **pure read**, unlike `GET /insights` — it never recomputes patterns (C-06 stays true: the
 * engine still runs in exactly one place). A digest fetched between two `GET /insights` calls
 * reflects whatever `recomputePatterns()` last wrote, the same staleness contract `GET
 * /insights/series` and `GET /insights/when` already have.
 *
 * Task 2's "if the digest API is unreachable at fire time, the notification simply opens Insights"
 * is a client-side fallback (`mobile/lib/core/notifications/reminder_service.dart`'s digest tap
 * handler) — nothing here needs to special-case an unreachable server, because the server being
 * unreachable is exactly the case in which this endpoint is never called at all.
 *
 * M-3 (#48): gated whole, not "computed but window-limited" the way patterns are — the issue lists
 * "weekly digest" itself, not a scoped-down version of it, as the premium feature (daylio-
 * competitive-analysis.md §11.2), and R-2's own ticket explicitly deferred this: "build it unguarded
 * now, gating arrives with M-3." `@RequiresPremium()` on the whole controller rather than only the
 * one handler it has today is future-proofing against a second route landing here unguarded by
 * omission, not a sign a second route is planned.
 */
@Controller('insights')
@RequiresPremium()
export class DigestController {
  constructor(private readonly digest: DigestService) {}

  /**
   * `week` is optional and, when given, any `YYYY-MM-DD` date inside the target week — see
   * `DigestService#get`'s doc comment for why a caller supplies the date rather than this reading
   * the clock itself (determinism, acceptance criterion 1).
   */
  @Get('digest')
  get(@Query('week') week: string | undefined, @Req() req: Request): DigestResponse {
    try {
      return this.digest.get(req.userId as string, week);
    } catch (err) {
      if (err instanceof InvalidDigestWeekError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
  }
}
