import { Controller, Get } from '@nestjs/common';
import { PatternsService, type PatternOut } from './patterns.service';

@Controller('insights')
export class InsightsController {
  constructor(private readonly patterns: PatternsService) {}

  /**
   * Recomputes before reading.
   *
   * This endpoint **writes** — `recomputePatterns()` rewrites `pattern_entries` on every call. That
   * is current behaviour, faithfully preserved, and it is why SC-011's "reading every screen leaves
   * the data unchanged" cannot be met literally without breaking SC-002. See the note at the top of
   * tasks.md and T072.
   */
  @Get()
  async get(): Promise<{ patterns: PatternOut[]; insufficient_data: boolean }> {
    await this.patterns.recomputePatterns();
    const patterns = this.patterns.listPatterns();
    // The client branches on this flag, not on array length.
    return { patterns, insufficient_data: patterns.length === 0 };
  }
}
