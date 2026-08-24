import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config';
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

/**
 * whisper.cpp is a local artifact, never committed: `tools/whisper/` is gitignored and a package
 * manager may put it anywhere. So the binary under test is the one `WHISPER_COMMAND` actually
 * points at — asserting on the build-from-source path alone failed on every clone that installed
 * whisper.cpp any other way, and on CI, which installs it not at all.
 *
 * Skipped rather than failed when nothing is installed: absent whisper.cpp the app degrades to
 * typed answers by design, so "no local speech runtime" is a supported state, not a broken build.
 */
describe('local speech-to-text runtime', () => {
  const command = loadConfig().whisperCommand;

  it.skipIf(!existsSync(command))(
    'starts the configured whisper executable with its adjacent shared libraries',
    () => {
      const result = spawnSync(command, ['--help'], {
        encoding: 'utf8',
        env: whisperProcessEnvironment(command),
      });

      expect(result.error).toBeUndefined();
      expect(result.status).toBe(0);
      expect(`${result.stdout}${result.stderr}`).toContain('usage:');
    },
    // Generous on purpose: the first exec of a freshly installed whisper.cpp pays a one-off cost
    // while the OS verifies the binary and its shared libraries, which overran the 5s default.
    30_000,
  );
});
