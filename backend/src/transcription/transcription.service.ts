import { Injectable } from '@nestjs/common';
import { execFile } from 'node:child_process';
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { promisify } from 'node:util';
import { loadConfig } from '../config';

const run = promisify(execFile);
const WHISPER_THREADS = Math.min(8, Math.max(1, os.availableParallelism()));

export class TranscriptionUnavailableError extends Error {}
export class InvalidAudioError extends Error {}

/** Let a bundled whisper executable resolve the shared libraries shipped beside it. */
export function whisperProcessEnvironment(
  command: string,
  base: NodeJS.ProcessEnv = process.env,
): NodeJS.ProcessEnv {
  const libraryDirectory = path.dirname(path.resolve(command));
  return {
    ...base,
    LD_LIBRARY_PATH: [libraryDirectory, base.LD_LIBRARY_PATH].filter(Boolean).join(path.delimiter),
  };
}

/** Keep model punctuation, but remove CLI line breaks and whitespace noise. */
export function normalizeTranscript(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

/**
 * Converts MediaRecorder output to the mono 16 kHz WAV whisper.cpp expects, then transcribes it
 * entirely on this machine. Audio lives only in a private temp directory and is always removed.
 */
@Injectable()
export class TranscriptionService {
  async transcribe(audio: Buffer): Promise<string> {
    const config = loadConfig();
    try {
      await fs.access(config.whisperModelPath);
    } catch {
      throw new TranscriptionUnavailableError(
        `The local speech model was not found at ${config.whisperModelPath}.`,
      );
    }

    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'diary-transcription-'));
    const sourcePath = path.join(directory, 'recording');
    const wavPath = path.join(directory, 'recording.wav');
    const outputPrefix = path.join(directory, 'transcript');

    try {
      await fs.writeFile(sourcePath, audio, { mode: 0o600 });
      try {
        await run(
          'ffmpeg',
          [
            '-nostdin',
            '-hide_banner',
            '-loglevel',
            'error',
            '-y',
            '-i',
            sourcePath,
            '-ar',
            '16000',
            '-ac',
            '1',
            '-c:a',
            'pcm_s16le',
            wavPath,
          ],
          { timeout: 30_000, maxBuffer: 1024 * 1024 },
        );
      } catch {
        throw new InvalidAudioError('The recording could not be decoded. Please record it again.');
      }

      try {
        await run(
          config.whisperCommand,
          [
            '-m',
            config.whisperModelPath,
            '-t',
            String(WHISPER_THREADS),
            '-f',
            wavPath,
            '-l',
            config.whisperLanguage,
            '-nt',
            '-np',
            '-otxt',
            '-of',
            outputPrefix,
          ],
          {
            timeout: config.transcriptionTimeoutMs,
            maxBuffer: 4 * 1024 * 1024,
            env: whisperProcessEnvironment(config.whisperCommand),
          },
        );
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (code === 'ENOENT') {
          throw new TranscriptionUnavailableError(
            `The local speech-to-text command "${config.whisperCommand}" is not installed.`,
          );
        }
        throw new TranscriptionUnavailableError('Local speech-to-text failed. Please try again.');
      }

      const transcript = normalizeTranscript(await fs.readFile(`${outputPrefix}.txt`, 'utf8'));
      if (!transcript) throw new InvalidAudioError('No speech was detected in that recording.');
      return transcript;
    } finally {
      await fs.rm(directory, { recursive: true, force: true });
    }
  }
}
