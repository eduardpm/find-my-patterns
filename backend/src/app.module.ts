import { Module, type DynamicModule } from '@nestjs/common';
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
import { InsightsController } from './insights/insights.controller';
import { EchoService } from './insights/echo.service';
import { PatternsService } from './insights/patterns.service';
import { SeriesService } from './insights/series.service';
import { WhenInsightsService } from './insights/when.service';
import { QuestionYieldController } from './insights/question-yield.controller';
import { QuestionYieldService } from './insights/question-yield.service';
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

@Module({})
export class AppModule {
  /**
   * `databasePath` is injectable so tests can point at a throwaway copy of the golden fixture.
   * In production the API can only enqueue inference jobs. Tests use an immediate deterministic
   * double so they neither need a background process nor connect to Ollama.
   */
  static forRoot(databasePath?: string): DynamicModule {
    return {
      module: AppModule,
      controllers: [
        HealthController,
        EntriesController,
        FeelingsController,
        GuidingQuestionsController,
        InsightsController,
        QuestionYieldController,
        TopicsController,
        MonthlySummaryController,
        TranscriptionController,
        GuidedDraftsController,
      ],
      providers: [
        createDiaryProvider(databasePath),
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
        WhenInsightsService,
        SeriesService,
        QuestionYieldService,
        EchoService,
        MonthlySummaryService,
        TranscriptionService,
        TranscriptionJobsService,
      ],
    };
  }
}
