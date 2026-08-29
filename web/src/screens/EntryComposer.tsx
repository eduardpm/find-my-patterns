import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { ApiFailure } from '../api/client';
import { createEntry, fetchEntryEcho, getEntry, updateEntry } from '../api/entries';
import { fetchInsights } from '../api/insights';
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
import { IntensityDials } from '../components/IntensityDial';
import { PatternEchoPanel } from '../components/PatternEchoPanel';
import type {
  EngineConstants,
  Entry,
  FeelingVocabulary,
  GuidedAnswerInput,
  GuidingQuestion,
  PatternEcho,
} from '../domain/types';
import { useUnsavedGuard } from '../hooks/useUnsavedGuard';
import { useRefreshable } from '../hooks/useRefreshable';
import { GuidedQuestionFlow } from './GuidedQuestionFlow';

/**
 * `echo` is a step, not a modal: after the feeling is confirmed the diary has something to say
 * about what was just written, and it gets its own screen rather than a toast that scrolls past
 * (I4). It is also the only stage the user can reach *after* their entry is fully stored, which is
 * the whole constraint the echo is under (I4-02).
 */
type Stage = 'guided' | 'writing' | 'suggesting' | 'confirming' | 'echo';

const EYEBROW: Record<Stage, string> = {
  guided: 'Step 1 of 2 · New entry',
  writing: 'Step 1 of 2 · New entry',
  suggesting: 'Step 1 of 2 · New entry',
  confirming: 'Step 2 of 2 · Saved',
  echo: 'Saved',
};

const TITLE: Record<Stage, string> = {
  guided: 'What just happened?',
  writing: 'What just happened?',
  suggesting: 'What just happened?',
  confirming: 'How did that feel?',
  echo: 'Entry saved',
};

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
  const { data: feelings } = useRefreshable<FeelingVocabulary>(
    useCallback(() => fetchFeelings(), []),
  );
  const { data: questions } = useRefreshable<GuidingQuestion[]>(
    useCallback(() => fetchGuidingQuestions(), []),
  );

  const [text, setText] = useState('');
  // Start guided: FR-004 says the composer opens with prompts rather than a blank field. Skipping
  // to freeform is one click away (FR-005).
  const [stage, setStage] = useState<Stage>('guided');
  const [saved, setSaved] = useState<Entry | null>(null);
  const [chosen, setChosen] = useState<string[]>([]);
  const [failure, setFailure] = useState<ApiFailure | null>(null);
  // Keyed by feeling, so unpicking a word takes its rating with it (I6).
  const [intensities, setIntensities] = useState<Record<string, number>>({});
  const [echoes, setEchoes] = useState<PatternEcho[]>([]);
  // The scale's bounds belong to the backend like every other threshold this client shows.
  const [constants, setConstants] = useState<EngineConstants | null>(null);
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

  useEffect(() => {
    void fetchInsights().then((result) => {
      if (result.ok) setConstants(result.value.constants);
    });
  }, []);

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
        // Only adopted while the user has not touched the control. The analyser arriving late must
        // never overwrite a choice already made by hand.
        setChosen((current) => (current.length > 0 ? current : result.value.feeling_keys));
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
    setChosen(suggestedKeysFor(result.value));
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
    setChosen(suggestedKeysFor(result.value));
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
    if (!saved || chosen.length === 0) return;
    setFailure(null);

    const result = await updateEntry(saved.id, {
      feeling_keys: chosen,
      feeling_intensities: intensities,
      version: saved.version,
    });
    if (!result.ok) {
      setFailure(result.error);
      return;
    }

    // I4-02: only now, with the entry stored and the feeling settled, is the diary asked what it
    // already knows about these topics. Nothing was on screen while the user was writing.
    const echo = await fetchEntryEcho(saved.id);
    if (echo.ok && echo.value.length > 0) {
      setEchoes(echo.value);
      setStage('echo');
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
            visible as a sequence rather than as the page unexpectedly changing its question. The
            echo is deliberately *after* the count — it is what the diary had to say once the entry
            was safely stored, not a third thing standing between the user and being finished.
          */}
          <span className="page-header__eyebrow">{EYEBROW[stage]}</span>
          <h1>{TITLE[stage]}</h1>
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

      {stage === 'echo' && saved && (
        <>
          <blockquote className="card entry-card__text">{saved.raw_text}</blockquote>
          <PatternEchoPanel echoes={echoes} onDismiss={() => navigate('/app/today')} />
          <div className="composer-actions">
            <button type="button" className="btn" onClick={() => navigate('/app/today')}>
              Done
              <Icon name="check" />
            </button>
          </div>
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
            legend="Pick the feelings that fit"
            vocabulary={feelings}
            selected={chosen}
            onChange={(keys) => {
              setChosen(keys);
              // A rating belongs to its feeling, so dropping a word drops its number too.
              setIntensities((current) =>
                Object.fromEntries(Object.entries(current).filter(([key]) => keys.includes(key))),
              );
            }}
            suggestedKeys={suggestedKeysFor(saved)}
          />
          {/* Optional, after the feelings and never before them (I6-07). */}
          {constants && (
            <IntensityDials
              feelings={chosen.flatMap(
                (key) => feelings?.feelings.filter((feeling) => feeling.key === key) ?? [],
              )}
              values={intensities}
              onChange={setIntensities}
              min={constants.min_intensity}
              max={constants.max_intensity}
            />
          )}
          <div className="composer-actions">
            <button
              type="button"
              className="btn"
              onClick={handleConfirm}
              disabled={chosen.length === 0}
            >
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

/**
 * What the backend is proposing for an entry, as keys.
 *
 * `suggested_feelings` is populated only while the analyser's answer differs from what the entry
 * already carries; once the two agree it is empty and the entry's own `feeling_keys` *are* the
 * suggestion. Reading both is what keeps the "suggested" marks on screen either way.
 */
function suggestedKeysFor(entry: Entry): string[] {
  if (entry.suggested_feelings.length > 0) {
    return entry.suggested_feelings.map((suggestion) => suggestion.key);
  }
  return entry.feeling_source === 'suggested' ? entry.feeling_keys : [];
}
