import { useEffect, useMemo, useState } from 'react';
import type { GuidedAnswerInput, GuidingQuestion } from '../domain/types';
import { AudioAnswerRecorder } from '../components/AudioAnswerRecorder';
import { Icon } from '../components/Icon';

/**
 * Decides which prompts to show for the text written so far.
 *
 * All mandatory core prompts always appear; a situational one appears once the text mentions
 * something it relates to. This is presentation logic — *which prompt to show* — not a claim about
 * the diary, so Principle VII permits it here. The questions and their trigger keywords still come
 * from the backend; nothing about the library is hardcoded in this file.
 *
 * Exported for its own test (T050) because "the right prompt appears at the right time" is the
 * whole substance of FR-004, and it is much easier to pin down as a pure function.
 */
export function selectPrompts(questions: GuidingQuestion[], textSoFar: string): GuidingQuestion[] {
  const haystack = textSoFar.toLowerCase();
  const mandatory = questions.filter((q) => q.is_mandatory);
  const triggered = questions.filter(
    (q) => !q.is_mandatory && q.trigger_keywords.some((kw) => haystack.includes(kw.toLowerCase())),
  );
  return [...mandatory, ...triggered];
}

interface Props {
  questions: GuidingQuestion[];
  draftKey: string;
  initialAnswers?: GuidedAnswerInput[];
  onSaveAnswer: (answer: GuidedAnswerInput, orderIndex: number) => Promise<boolean>;
  onComplete: (answers: GuidedAnswerInput[]) => void;
  onSkip: () => void;
  onDirtyChange?: (dirty: boolean) => void;
  busy?: boolean;
}

/**
 * Walks the user through the prompts instead of showing a blank page (FR-004).
 *
 * The prompt list is recomputed from what they've written so far, so answering the general question
 * with "I drank a coke and felt awful" pulls in the food/drink prompt — the flow follows the entry
 * rather than interrogating from a fixed script. Skipping to freeform is always available (FR-005):
 * the framework is a scaffold, not a restriction.
 */
export function GuidedQuestionFlow({
  questions,
  draftKey,
  initialAnswers = [],
  onSaveAnswer,
  onComplete,
  onSkip,
  onDirtyChange,
  busy = false,
}: Props) {
  const [answers, setAnswers] = useState<GuidedAnswerInput[]>(initialAnswers);
  const [draft, setDraft] = useState('');
  const [audioBusy, setAudioBusy] = useState(false);
  const [audioPending, setAudioPending] = useState(false);
  const [savingAnswer, setSavingAnswer] = useState(false);
  const [saveError, setSaveError] = useState('');

  useEffect(() => {
    onDirtyChange?.(answers.length > 0 || draft.trim().length > 0 || audioBusy || audioPending);
  }, [answers, draft, audioBusy, audioPending, onDirtyChange]);

  const answeredText = useMemo(() => answers.map((a) => a.answer_text).join(' '), [answers]);
  const prompts = useMemo(
    () => selectPrompts(questions, `${answeredText} ${draft}`),
    [questions, answeredText, draft],
  );

  const index = answers.length;
  const current = prompts[index] ?? null;
  const isLast = index >= prompts.length - 1;

  function commit(): GuidedAnswerInput[] {
    const next = [...answers, { question_key: current!.key, answer_text: draft.trim() }];
    setAnswers(next);
    setDraft('');
    return next;
  }

  async function persistCurrent(): Promise<GuidedAnswerInput[] | null> {
    if (!current || !draft.trim()) return null;
    const answer = { question_key: current.key, answer_text: draft.trim() };
    setSavingAnswer(true);
    setSaveError('');
    const saved = await onSaveAnswer(answer, answers.length);
    setSavingAnswer(false);
    if (!saved) {
      setSaveError('That answer was not saved. Your text is still here—please try again.');
      return null;
    }
    return commit();
  }

  async function handleNext() {
    const next = await persistCurrent();
    if (!next) return;
    // Recompute against the answer just given: it may itself have surfaced a new prompt.
    if (selectPrompts(questions, next.map((a) => a.answer_text).join(' ')).length <= next.length) {
      onComplete(next);
    }
  }

  async function handleFinish() {
    const next = await persistCurrent();
    if (next) onComplete(next);
  }

  if (!current) {
    return (
      <div className="empty-state">
        <span className="empty-state__icon">
          <Icon name="spark" size="1.5rem" />
        </span>
        <p className="empty-state__title">No prompts available</p>
        <p>The question library came back empty, so this one is a blank page after all.</p>
        <button type="button" className="btn" onClick={onSkip}>
          Just write freely
        </button>
      </div>
    );
  }

  return (
    <div className="stack">
      {/*
        The prompt list grows as the user writes — mentioning a drink pulls in the drink prompt — so
        the visible track is drawn as one segment per prompt rather than as a filling bar. A bar
        would appear to slide backwards the moment the denominator rose, which would read as lost
        progress. Only the sentence is announced; the segments are decoration on top of it.
      */}
      <div className="composer-progress">
        <p className="composer-progress__label">
          <span aria-live="polite">
            Question {index + 1} of {prompts.length}
          </span>
          <span>{isLast ? 'Last one' : `${prompts.length - index - 1} to go`}</span>
        </p>
        <div className="composer-progress__track" aria-hidden="true">
          {prompts.map((prompt, i) => (
            <span
              key={prompt.key}
              className={`composer-progress__step${
                i < index
                  ? ' composer-progress__step--done'
                  : i === index
                    ? ' composer-progress__step--current'
                    : ''
              }`}
            />
          ))}
        </div>
      </div>

      <label className="guided-prompt" htmlFor="guided-answer">
        {current.prompt_text}
      </label>
      <textarea
        id="guided-answer"
        className="textarea"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
            e.preventDefault();
            if (isLast) void handleFinish();
            else void handleNext();
          }
        }}
        autoFocus
      />

      <AudioAnswerRecorder
        key={current.key}
        draftKey={draftKey}
        questionKey={current.key}
        orderIndex={index}
        disabled={busy}
        onBusyChange={setAudioBusy}
        onPendingChange={setAudioPending}
        onTranscript={(transcript) =>
          setDraft((existing) => `${existing.trim()}${existing.trim() ? ' ' : ''}${transcript}`)
        }
      />

      {saveError && (
        <p className="audio-answer__error" role="alert">
          {saveError}
        </p>
      )}

      {/*
        The two actions are not peers — one advances the flow, the other abandons it — so "skip" is
        pushed to the far side rather than sat next to the primary button where a fast hand would
        reach it by momentum.
      */}
      <div className="composer-actions">
        <button
          type="button"
          className="btn"
          onClick={() => void (isLast ? handleFinish() : handleNext())}
          disabled={!draft.trim() || busy || audioBusy || audioPending || savingAnswer}
        >
          {busy || savingAnswer ? 'Saving…' : isLast ? 'Done' : 'Next'}
          {!busy && !savingAnswer && <Icon name={isLast ? 'check' : 'chevronRight'} />}
        </button>
        <button
          type="button"
          className="btn btn--text composer-actions__aside"
          onClick={onSkip}
          disabled={busy || audioBusy || audioPending || savingAnswer}
        >
          Skip the questions and just write
        </button>
      </div>
    </div>
  );
}
