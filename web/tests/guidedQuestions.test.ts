/**
 * FR-004: the composer offers the same guiding prompts as the phone.
 *
 * The mandatory general prompt always shows; the situational ones surface only when the text so far
 * mentions something they relate to (research.md §1). This is presentation logic — deciding which
 * prompt to *show* — not a fact about the diary, so it is allowed to live in the client under
 * Principle VII. The questions themselves, including their trigger keywords, come from the backend.
 */

import { describe, expect, it } from 'vitest';
import { selectPrompts } from '../src/screens/GuidedQuestionFlow';
import type { GuidingQuestion } from '../src/domain/types';

const QUESTIONS: GuidingQuestion[] = [
  {
    key: 'general_feeling',
    category: 'general',
    prompt_text: 'What happened?',
    trigger_keywords: [],
    is_mandatory: true,
  },
  {
    key: 'mind_body',
    category: 'mind_body',
    prompt_text: 'What did you notice in your mind and body?',
    trigger_keywords: [],
    is_mandatory: true,
  },
  {
    key: 'small_influences',
    category: 'small_influences',
    prompt_text: 'What small things might have influenced you?',
    trigger_keywords: [],
    is_mandatory: true,
  },
  {
    key: 'response_outcome',
    category: 'response_outcome',
    prompt_text: 'What did you do next, and what changed afterward?',
    trigger_keywords: ['stressed', 'sad', 'overwhelmed', 'happy', 'proud'],
    is_mandatory: false,
  },
];

const keys = (qs: GuidingQuestion[]) => qs.map((q) => q.key);

describe('selectPrompts', () => {
  it('always includes all three core prompts, even with no text', () => {
    expect(keys(selectPrompts(QUESTIONS, ''))).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
    ]);
  });

  it('does not surface situational prompts that nothing has triggered', () => {
    expect(keys(selectPrompts(QUESTIONS, 'Just a normal morning.'))).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
    ]);
  });

  it('surfaces the response-and-outcome follow-up for a notable experience', () => {
    expect(keys(selectPrompts(QUESTIONS, 'I felt overwhelmed after the meeting'))).toContain(
      'response_outcome',
    );
  });

  it('also follows up on a notably positive experience', () => {
    expect(keys(selectPrompts(QUESTIONS, 'I felt proud of myself'))).toContain('response_outcome');
  });

  it('matches keywords case-insensitively', () => {
    expect(keys(selectPrompts(QUESTIONS, 'I felt OVERWHELMED'))).toContain('response_outcome');
  });

  it('keeps all mandatory prompts before the follow-up', () => {
    expect(keys(selectPrompts(QUESTIONS, 'I felt proud'))).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
      'response_outcome',
    ]);
  });

  it('never repeats a prompt when several of its keywords match', () => {
    const selected = keys(selectPrompts(QUESTIONS, 'I felt stressed, sad, and overwhelmed'));

    expect(selected.filter((k) => k === 'response_outcome')).toHaveLength(1);
  });

  it('returns all mandatory prompts when the library has no optional follow-up', () => {
    const mandatoryOnly = QUESTIONS.filter((q) => q.is_mandatory);

    expect(keys(selectPrompts(mandatoryOnly, 'I felt stressed'))).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
    ]);
  });

  it('handles an empty question library without throwing', () => {
    expect(selectPrompts([], 'anything')).toEqual([]);
  });
});
