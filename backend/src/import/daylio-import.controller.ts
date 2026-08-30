import {
  Body,
  Controller,
  HttpCode,
  HttpException,
  HttpStatus,
  Post,
  Req,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import type { Request } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { DaylioCsvFormatError } from './daylio-csv-parser';
import {
  DaylioContentHashCollisionError,
  DaylioImportService,
  DaylioReportHashMismatchError,
  type CollisionEntry,
  type DaylioCommitResult,
  type DaylioDryRunReport,
  type MoodMappingEntry,
  type RowError,
  type UnmappedMood,
} from './daylio-import.service';

/**
 * The shape multer's memory storage actually hands `@UploadedFile()` at runtime. Declared locally
 * rather than depending on `@types/multer` (not a project dependency) purely for the type; this is
 * a structural match, not a different runtime contract.
 */
interface UploadedCsvFile {
  buffer: Buffer;
  originalname: string;
  mimetype: string;
  size: number;
}

/**
 * Generous but bounded: years of Daylio history at a few entries a day is a few thousand rows,
 * comfortably under a megabyte of CSV. 10MB leaves headroom for long notes without accepting an
 * unbounded upload.
 */
const MAX_CSV_BYTES = 10 * 1024 * 1024;
const UPLOAD_OPTIONS = { limits: { fileSize: MAX_CSV_BYTES } };

function requireFile(file: UploadedCsvFile | undefined): UploadedCsvFile {
  if (!file || !Buffer.isBuffer(file.buffer) || file.buffer.length === 0) {
    throw new HttpException(
      'A CSV file is required (multipart field "file").',
      HttpStatus.UNPROCESSABLE_ENTITY,
    );
  }
  return file;
}

function toRowErrorOut(row: RowError): Record<string, unknown> {
  return { row: row.rowNumber, reason: row.reason };
}

function toMoodMappingOut(entry: MoodMappingEntry): Record<string, unknown> {
  return { daylio_mood: entry.daylioMood, feeling_key: entry.feelingKey };
}

function toUnmappedMoodOut(entry: UnmappedMood): Record<string, unknown> {
  return { mood: entry.mood, count: entry.count, sample_rows: entry.rowNumbers };
}

function toCollisionOut(entry: CollisionEntry): Record<string, unknown> {
  return { row: entry.rowNumber, entry_date: entry.entryDate, reason: entry.reason };
}

function toDryRunOut(report: DaylioDryRunReport): Record<string, unknown> {
  return {
    content_hash: report.contentHash,
    report_hash: report.reportHash,
    total_rows: report.totalRows,
    parseable_count: report.parseableCount,
    importable_count: report.importableCount,
    unparseable_rows: report.unparseableRows.map(toRowErrorOut),
    mood_mapping: report.moodMapping.map(toMoodMappingOut),
    unmapped_moods: report.unmappedMoods.map(toUnmappedMoodOut),
    date_range: report.dateRange,
    collisions: report.collisions.map(toCollisionOut),
    already_imported: report.alreadyImported,
    previous_import: report.previousImport
      ? {
          imported_at: report.previousImport.importedAt,
          entry_count: report.previousImport.entryCount,
        }
      : null,
  };
}

function toCommitOut(result: DaylioCommitResult): Record<string, unknown> {
  return {
    idempotent: result.idempotent,
    imported_count: result.importedCount,
    skipped_unmapped_count: result.skippedUnmappedCount,
    entry_ids: result.entryIds,
    content_hash: result.contentHash,
    previous_import: result.previousImport
      ? {
          imported_at: result.previousImport.importedAt,
          entry_count: result.previousImport.entryCount,
        }
      : null,
  };
}

/**
 * The Daylio CSV two-phase import (L-1b, #35) — see `backend/docs/import.md`.
 *
 * `POST /import/daylio/dry-run` parses and reports; `POST /import/daylio/commit` writes, and only
 * after checking the report it just recomputed against the `report_hash` the caller says it
 * accepted. Neither endpoint issues DDL or touches the schema — both write through
 * `EntriesService`/`TopicsService`, the same as every other entry point that creates diary content.
 */
@Controller('import/daylio')
export class DaylioImportController {
  constructor(private readonly imports: DaylioImportService) {}

  @Post('dry-run')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', UPLOAD_OPTIONS))
  dryRun(
    @UploadedFile() file: UploadedCsvFile | undefined,
    @Req() req: Request,
  ): Record<string, unknown> {
    const upload = requireFile(file);
    try {
      return toDryRunOut(this.imports.dryRun(req.userId as string, upload.buffer));
    } catch (err) {
      if (err instanceof DaylioCsvFormatError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      throw err;
    }
  }

  @Post('commit')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', UPLOAD_OPTIONS))
  commit(
    @UploadedFile() file: UploadedCsvFile | undefined,
    @Body('report_hash') reportHash: string | undefined,
    @Req() req: Request,
  ): Record<string, unknown> {
    const upload = requireFile(file);
    if (!reportHash || !/^[0-9a-f]{64}$/i.test(reportHash)) {
      throw new HttpException(
        'Field required: report_hash (the sha256 hex string a dry-run of this file returned).',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    try {
      return toCommitOut(this.imports.commit(req.userId as string, upload.buffer, reportHash));
    } catch (err) {
      if (err instanceof DaylioCsvFormatError || err instanceof DaylioReportHashMismatchError) {
        throw new HttpException(err.message, HttpStatus.UNPROCESSABLE_ENTITY);
      }
      // See `DaylioContentHashCollisionError`'s doc comment (`daylio-import.service.ts`):
      // `csv_imports.content_hash` is still a global primary key, so this is a real, tracked,
      // deliberately-deferred multi-tenant limitation, not a bug this ticket introduces. 409, not
      // 422: the request was perfectly well-formed, the file's identity just collides with a
      // resource (another account's import record) this caller cannot see or resolve.
      if (err instanceof DaylioContentHashCollisionError) {
        throw new HttpException(err.message, HttpStatus.CONFLICT);
      }
      throw err;
    }
  }
}
