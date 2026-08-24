import {
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
import { TranscriptionJobsService, type TranscriptionJob } from './transcription-jobs.service';

@Controller('transcriptions')
export class TranscriptionController {
  constructor(private readonly jobs: TranscriptionJobsService) {}

  @Post()
  @HttpCode(HttpStatus.ACCEPTED)
  create(@Req() request: Request): { id: string; status: 'pending' } {
    const contentType = request.get('content-type')?.split(';', 1)[0].trim().toLowerCase() ?? '';
    if (!contentType.startsWith('audio/')) {
      throw new HttpException(
        'An audio content type is required.',
        HttpStatus.UNSUPPORTED_MEDIA_TYPE,
      );
    }
    if (!Buffer.isBuffer(request.body) || request.body.length === 0) {
      throw new HttpException('The recording is empty.', HttpStatus.UNPROCESSABLE_ENTITY);
    }

    return { id: this.jobs.start(request.body), status: 'pending' };
  }

  @Get(':jobId')
  get(@Param('jobId') jobId: string): TranscriptionJob {
    const job = this.jobs.find(jobId);
    if (!job) throw new HttpException('Transcription not found.', HttpStatus.NOT_FOUND);
    return job;
  }
}
