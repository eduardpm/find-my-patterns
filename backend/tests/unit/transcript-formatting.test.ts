import { describe, expect, it } from 'vitest';
import {
  acceptFormattedTranscript,
  ensureTranscriptParagraphs,
  projectTranscriptFormatting,
  transcriptWordSequence,
} from '../../src/inference/worker';

describe('lossless transcript formatting guard', () => {
  const original = 'Sleep was bad alcohol made me itchy caffeine made me jittery';

  it('accepts punctuation, casing, paragraphs, and bullet markers', () => {
    const formatted = 'Sleep was bad.\n\n- Alcohol made me itchy.\n- Caffeine made me jittery.';
    expect(acceptFormattedTranscript(original, formatted)).toBe(formatted);
  });

  it('rejects even a plausible grammar correction', () => {
    const changed = 'Sleep was bad. Alcohol makes me itchy. Caffeine made me jittery.';
    expect(acceptFormattedTranscript(original, changed)).toBe(original);
  });

  it('rejects omitted or reordered words', () => {
    expect(acceptFormattedTranscript(original, 'Sleep was bad. Caffeine made me jittery.')).toBe(
      original,
    );
    expect(
      acceptFormattedTranscript(
        original,
        'Alcohol made me itchy. Sleep was bad. Caffeine made me jittery.',
      ),
    ).toBe(original);
  });

  it('compares unicode words case-insensitively', () => {
    expect(transcriptWordSequence('Énergie—LAAG, café.')).toEqual(['énergie', 'laag', 'café']);
  });

  it('projects useful punctuation while discarding a model-added word', () => {
    const source = 'Today I was tired then work was hard later I rested';
    const candidate = 'Today, I was very tired. Then work was hard. Later, I rested.';
    const projected = 'Today, I was tired. Then work was hard. Later, I rested.';

    expect(projectTranscriptFormatting(source, candidate)).toBe(projected);
    expect(transcriptWordSequence(projected)).toEqual(transcriptWordSequence(source));
  });

  it('rejects a candidate that rewrites too much to be a safe formatting stencil', () => {
    const source = 'problems in my father slight figure out';
    const rewritten = 'problems with my father slightly figure it out';
    expect(projectTranscriptFormatting(source, rewritten)).toBe(source);
  });

  it('reflows a long text wall only at sentence boundaries', () => {
    const sentence = (prefix: string, count: number): string =>
      `${Array.from({ length: count }, (_, index) => `${prefix}${index}`).join(' ')}.`;
    const source = `${sentence('a', 50)} ${sentence('b', 50)} ${sentence('c', 30)}`;
    const reflowed = ensureTranscriptParagraphs(source);

    expect(reflowed.split('\n\n')).toHaveLength(3);
    expect(reflowed.replace(/\n\n/g, ' ')).toBe(source);
    expect(transcriptWordSequence(reflowed)).toEqual(transcriptWordSequence(source));
  });
});
