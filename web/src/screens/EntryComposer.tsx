import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { ApiFailure } from '../api/client';
import { createEntry, getEntry, updateEntry } from '../api/entries';
import { fetchFeelings } from '../api/feelings';
import { fetchGuidingQuestions } from '../api/guidingQuestions';
import {
  createGuidedDraft,
  deleteGuidedDraft,
  finalizeGuidedDraft,
  getGuidedDraft,
  saveGuidedDraftAnswer,
} from '../api/guidedDrafts';
import { ErrorBanner } from '../components/ErrorBanner';
import { FeelingChips } from '../components/FeelingChips';
import { Icon } from '../components/Icon';
import type { Entry, Feeling, GuidedAnswerInput, GuidingQuestion } from '../domain/types';
import { useUnsavedGuard } from '../hooks/useUnsavedGuard';
import { useRefreshable } from '../hooks/useRefreshable';
import { GuidedQuestionFlow } from './GuidedQuestionFlow';

type Stage = 'guided' | 'writing' | 'suggesting' | 'confirming';

/**
 * The freeform composer, and the reason this feature exists: writing at a real keyboard should be
 * faster and more pleasant than on a phone (SC-001/SC-002).
 *
 * The flow is deliberately two steps, matching the Android app: save the text, let the backend
 * suggest a feeling, then confirm or override it (FR-005). The entry is already persisted before
 * the confirm step, so a browser crash mid-confirm costs the feeling, never the writing.
 */
export function EntryComposer() {
  const navigate = useNavigate();
  const { data: feelings } = useRefreshable<Feeling[]>(useCallback(() => fetchFeelings(), []));
  const { data: questions } = useRefreshable<GuidingQuestion[]>(
    useCallback(() => fetchGuidingQuestions(), []),
  );

  const [text, setText] = useState('');
  // Start guided: FR-004 says the composer opens with prompts rather than a blank field. Skipping
  // to freeform is one click away (FR-005).
  const [stage, setStage] = useState<Stage>('guided');
  const [saved, setSaved] = useState<Entry | null>(null);
  const [chosen, setChosen] = useState<string | null>(null);
  const [failure, setFailure] = useState<ApiFailure | null>(null);
  const [guidedDirty, setGuidedDirty] = useState(false);
  const [draftKey, setDraftKey] = useState<string | null>(null);
  const [initialAnswers, setInitialAnswers] = useState<GuidedAnswerInput[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const draftInitializationStarted = useRef(false);

  useEffect(() => {
    if (draftInitializationStarted.current) return;
    draftInitializationStarted.current = true;

    async function initializeDraft() {
      const created = await createGuidedDraft();
      if (!created.ok) {
        setFailure(created.error);
        return;
      }
      const key = created.value.draft_key;
      const existing = await getGuidedDraft(key);
      if (!existing.ok) {
        setFailure(existing.error);
        return;
      }
      setInitialAnswers(existing.value.answers);
      setDraftKey(key);
    }

    void initializeDraft();
  }, []);

  // Dirty while there is text that hasn't reached the backend. Once saved, the writing is safe, so
  // the guard stands down even though the feeling may still be unconfirmed (FR-026).
  const { confirmDiscard } = useUnsavedGuard(
    (stage === 'writing' && text.trim().length > 0) ||
      (stage === 'guided' && guidedDirty) ||
      stage === 'suggesting',
  );

  // Depends on `stage`, not `[]`: the freeform textarea doesn't exist while the guided flow is
  // showing, so a mount-only effect focused nothing and left a keyboard user stranded after
  // choosing "skip the questions" — they had to tab back to the writing area (FR-014).
  useEffect(() => {
    if (stage === 'writing') textareaRef.current?.focus();
  }, [stage]);

  // Saving never waits for local inference. Observe the worker's later update while leaving the
  // feeling controls usable, so a cold model cannot hold the entry or the user hostage.
  useEffect(() => {
    if (stage !== 'confirming' || !saved || saved.feeling_source !== 'unset') return;

    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = Date.now() + 2 * 60 * 1000;

    const poll = async () => {
      const result = await getEntry(saved.id);
      if (stopped) return;
      if (result.ok && result.value.feeling_source !== 'unset') {
        setSaved(result.value);
        setChosen((current) => current ?? result.value.feeling_key);
        return;
      }
      if (Date.now() < deadline) timer = setTimeout(() => void poll(), 1_000);
    };

    timer = setTimeout(() => void poll(), 1_000);
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [stage, saved]);

  async function submitFreeform(rawText: string) {
    setStage('suggesting');
    setFailure(null);

    const result = await createEntry({ mode: 'freeform', raw_text: rawText });

    if (!result.ok) {
      // FR-013/SC-007: never let a failed save look like a successful one.
      setFailure(result.error);
      setStage('writing');
      return;
    }

    setSaved(result.value);
    setChosen(result.value.suggested_feeling?.key ?? result.value.feeling_key ?? null);
    setStage('confirming');
  }

  function handleSave() {
    if (!text.trim() || stage !== 'writing') return;
    void submitFreeform(text);
  }

  /**
   * Guided answers are sent as structured `guided_answers`, not flattened into free text — the
   * backend stores each answer against its question so pattern detection can use the structure
   * exactly as it does for entries written on the phone (FR-004, US3 AC4).
   */
  async function handleGuidedComplete() {
    if (!draftKey) return;
    setStage('suggesting');
    setFailure(null);
    const result = await finalizeGuidedDraft(draftKey);
    if (!result.ok) {
      setFailure(result.error);
      const restored = await getGuidedDraft(draftKey);
      if (restored.ok) setInitialAnswers(restored.value.answers);
      setStage('guided');
      return;
    }
    setSaved(result.value);
    setChosen(result.value.suggested_feeling?.key ?? result.value.feeling_key ?? null);
    setStage('confirming');
  }

  async function saveGuidedAnswer(answer: GuidedAnswerInput, orderIndex: number): Promise<boolean> {
    if (!draftKey) return false;
    const result = await saveGuidedDraftAnswer(draftKey, answer, orderIndex);
    if (!result.ok) setFailure(result.error);
    return result.ok;
  }

  async function skipGuidedQuestions() {
    if (!confirmDiscard()) return;
    if (draftKey) void deleteGuidedDraft(draftKey);
    setStage('writing');
  }

  async function handleConfirm() {
    if (!saved || !chosen) return;
    setFailure(null);

    const result = await updateEntry(saved.id, { feeling_key: chosen, version: saved.version });
    if (!result.ok) {
      setFailure(result.error);
      return;
    }
    navigate('/app/today');
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    // Ctrl/Cmd+Enter saves without reaching for the mouse (FR-014, SC-003).
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault();
      void handleSave();
    }
  }

  return (
    <div className="stack stack--loose">
      <header className="page-header">
        <div className="page-header__titles">
          {/*
            The eyebrow names the step so the two-stage save (write, then confirm the feeling) is
            visible as a sequence rather than as the page unexpectedly changing its question.
          */}
          <span className="page-header__eyebrow">
            {stage === 'confirming' ? 'Step 2 of 2 · Saved' : 'Step 1 of 2 · New entry'}
          </span>
          <h1>{stage === 'confirming' ? 'How did that feel?' : 'What just happened?'}</h1>
        </div>
      </header>

      <ErrorBanner failure={failure} />

      {stage === 'guided' && draftKey && (
        <GuidedQuestionFlow
          key={draftKey}
          questions={questions ?? []}
          draftKey={draftKey}
          initialAnswers={initialAnswers}
          onSaveAnswer={saveGuidedAnswer}
          onComplete={() => void handleGuidedComplete()}
          onSkip={() => void skipGuidedQuestions()}
          onDirtyChange={setGuidedDirty}
        />
      )}

      {stage === 'guided' && !draftKey && (
        <p className="muted" role="status">
          Preparing a safe draft…
        </p>
      )}

      {(stage === 'writing' || stage === 'suggesting') && (
        <>
          <label htmlFor="entry-text" className="visually-hidden">
            Your diary entry
          </label>
          <textarea
            id="entry-text"
            ref={textareaRef}
            className="textarea"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Write whatever's on your mind…"
            disabled={stage === 'suggesting'}
          />
          <div className="composer-actions">
            <button
              type="button"
              className="btn"
              onClick={handleSave}
              disabled={!text.trim() || stage === 'suggesting'}
            >
              {stage === 'suggesting' ? 'Saving…' : 'Save'}
              {stage !== 'suggesting' && <Icon name="check" />}
            </button>
            <span className="field-hint">
              <kbd>Ctrl</kbd> + <kbd>Enter</kbd>
            </span>
          </div>
          {stage === 'suggesting' && (
            <p className="muted" role="status">
              Saving your entry and working out how that sounded…
            </p>
          )}
        </>
      )}

      {stage === 'confirming' && saved && (
        <>
          <blockquote className="card entry-card__text">{saved.raw_text}</blockquote>
          {saved.feeling_source === 'unset' && (
            <p className="muted" role="status">
              Entry saved. Local feeling analysis is still running; you can choose now or wait.
            </p>
          )}
          <FeelingChips
            legend="Pick the feeling that fits"
            feelings={feelings ?? []}
            selected={chosen}
            onSelect={setChosen}
            suggestedKey={
              saved.suggested_feeling?.key ??
              (saved.feeling_source === 'suggested' ? saved.feeling_key : null)
            }
          />
          <div className="composer-actions">
            <button type="button" className="btn" onClick={handleConfirm} disabled={!chosen}>
              Done
              <Icon name="check" />
            </button>
            <button
              type="button"
              className="btn btn--text composer-actions__aside"
              onClick={() => navigate('/app/today')}
            >
              Skip for now
            </button>
          </div>
        </>
      )}
    </div>
  );
}
