import { Module, type DynamicModule } from '@nestjs/common';
import { AuthController } from './auth/identity.controller';
import { AuthService } from './auth/identity.service';
import {
  EntitlementsController,
  MANUAL_ENTITLEMENTS,
  PLAY_VERIFIER,
} from './billing/entitlements.controller';
import { EntitlementsService } from './billing/entitlements.service';
import {
  GooglePlayVerifier,
  ManualPlayVerifier,
  type PlayPurchaseVerifier,
} from './billing/play-verifier';
import { loadConfig } from './config';
import { createDiaryProvider } from './db/database.provider';
import {
  EntriesController,
  FeelingsController,
  GuidingQuestionsController,
} from './entries/entries.controller';
import {
  EntriesRepository,
  FeelingsRepository,
  GuidingQuestionsRepository,
} from './entries/entries.repository';
import { EntriesService } from './entries/entries.service';
import { GuidedDraftsController } from './entries/guided-drafts.controller';
import { ExportController } from './entries/export.controller';
import { ExportService } from './entries/export.service';
import { InsightsController } from './insights/insights.controller';
import { DigestController } from './insights/digest.controller';
import { DigestService } from './insights/digest.service';
import { EchoService } from './insights/echo.service';
import { ProgressService } from './insights/progress.service';
import { PatternsService } from './insights/patterns.service';
import { SeriesService } from './insights/series.service';
import { WhenInsightsService } from './insights/when.service';
import { QuestionYieldController } from './insights/question-yield.controller';
import { QuestionYieldService } from './insights/question-yield.service';
import { ExperimentsController } from './experiments/experiments.controller';
import { ExperimentsService } from './experiments/experiments.service';
import {
  ENTRY_INFERENCE,
  ImmediateTestInference,
  ImmediateTestTranscriptFormatting,
  QueuedEntryInference,
  QueuedTranscriptFormatting,
  TRANSCRIPT_FORMATTING,
} from './inference/inference';
import { MonthlySummaryController } from './monthly-summary/monthly-summary.controller';
import { MonthlySummaryService } from './monthly-summary/monthly-summary.service';
import { TopicsController } from './topics/topics.controller';
import { TopicsService } from './topics/topics.service';
import { HealthController } from './health.controller';
import { TranscriptionController } from './transcription/transcription.controller';
import { TranscriptionJobsService } from './transcription/transcription-jobs.service';
import { TranscriptionService } from './transcription/transcription.service';
import { DaylioImportController } from './import/daylio-import.controller';
import { DaylioImportService } from './import/daylio-import.service';

@Module({})
export class AppModule {
  /**
   * `databasePath` is injectable so tests can point at a throwaway copy of the golden fixture.
   * In production the API can only enqueue inference jobs. Tests use an immediate deterministic
   * double so they neither need a background process nor connect to Ollama.
   *
   * `options.playVerifier` and `options.manualEntitlements` (M-2, #47) mirror that same shape for
   * billing: a caller-supplied verifier wins outright over whatever `manualEntitlements` would
   * otherwise select, and `options.manualEntitlements` overrides `AppConfig.billing.
   * manualEntitlements` (`config.ts`) the same way `CreateAppOptions.singleUserMode` overrides
   * `AppConfig.singleUserMode` in `main.ts` — per-boot injection instead of `MANUAL_ENTITLEMENTS`,
   * a process env var this suite's test files share a single worker thread with. This is what lets
   * `tests/contract/billing.test.ts` boot one app with the real dev-mode gate on (exercising
   * `POST /billing/admin/grant`'s 404-when-off behaviour) and another with a `FakePlayVerifier`
   * (`billing/fake-play-verifier.ts`) standing in for a real Play response, without either test
   * touching the network or a shared env var.
   */
  static forRoot(
    databasePath?: string,
    options: { playVerifier?: PlayPurchaseVerifier; manualEntitlements?: boolean } = {},
  ): DynamicModule {
    return {
      module: AppModule,
      controllers: [
        HealthController,
        AuthController,
        EntriesController,
        FeelingsController,
        GuidingQuestionsController,
        InsightsController,
        DigestController,
        QuestionYieldController,
        ExperimentsController,
        TopicsController,
        MonthlySummaryController,
        TranscriptionController,
        GuidedDraftsController,
        ExportController,
        DaylioImportController,
        EntitlementsController,
      ],
      providers: [
        createDiaryProvider(databasePath),
        AuthService,
        EntitlementsService,
        {
          // M-2, #47: `MANUAL_ENTITLEMENTS` (`config.ts`) decides both which verifier backs
          // `POST /billing/play/verify` and whether `POST /billing/admin/grant` answers at all
          // (`EntitlementsController`) — one flag, read once here, rather than two places that
          // could disagree about whether dev mode is on.
          provide: MANUAL_ENTITLEMENTS,
          useFactory: (): boolean =>
            options.manualEntitlements ?? loadConfig().billing.manualEntitlements,
        },
        {
          provide: PLAY_VERIFIER,
          useFactory: (manualEntitlements: boolean): PlayPurchaseVerifier => {
            if (options.playVerifier) return options.playVerifier;
            return manualEntitlements
              ? new ManualPlayVerifier()
              : new GooglePlayVerifier(loadConfig().billing.googlePlay);
          },
          inject: [MANUAL_ENTITLEMENTS],
        },
        QueuedEntryInference,
        QueuedTranscriptFormatting,
        {
          provide: ENTRY_INFERENCE,
          useFactory: (queued: QueuedEntryInference) =>
            process.env.NODE_ENV === 'test' ? new ImmediateTestInference() : queued,
          inject: [QueuedEntryInference],
        },
        {
          provide: TRANSCRIPT_FORMATTING,
          useFactory: (queued: QueuedTranscriptFormatting) =>
            process.env.NODE_ENV === 'test' ? new ImmediateTestTranscriptFormatting() : queued,
          inject: [QueuedTranscriptFormatting],
        },
        EntriesRepository,
        FeelingsRepository,
        GuidingQuestionsRepository,
        EntriesService,
        TopicsService,
        PatternsService,
        DigestService,
        ExperimentsService,
        WhenInsightsService,
        SeriesService,
        QuestionYieldService,
        EchoService,
        ProgressService,
        MonthlySummaryService,
        TranscriptionService,
        TranscriptionJobsService,
        ExportService,
        DaylioImportService,
      ],
    };
  }
}
