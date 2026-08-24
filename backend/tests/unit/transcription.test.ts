import { spawnSync } from 'node:child_process';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  normalizeTranscript,
  whisperProcessEnvironment,
} from '../../src/transcription/transcription.service';

describe('transcription text normalization', () => {
  it('preserves words and punctuation while flattening whisper output whitespace', () => {
    expect(normalizeTranscript('  I felt tired.\n\nThen I went outside.  ')).toBe(
      'I felt tired. Then I went outside.',
    );
  });
});

describe('bundled speech-to-text runtime', () => {
  it('starts the actual whisper executable with its adjacent shared libraries', () => {
    const command = path.resolve(__dirname, '../../../tools/whisper/bin/whisper-cli');
    const result = spawnSync(command, ['--help'], {
      encoding: 'utf8',
      env: whisperProcessEnvironment(command),
    });

    expect(result.error).toBeUndefined();
    expect(result.status).toBe(0);
    expect(`${result.stdout}${result.stderr}`).toContain('usage:');
  });
});
