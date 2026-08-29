import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import type { ApiFailure } from '../api/client';
import { deleteEntry, fetchEntryEcho, getEntry, updateEntry } from '../api/entries';
import { ConflictView } from './ConflictScreen';
import { fetchFeelings } from '../api/feelings';
import { ErrorBanner } from '../components/ErrorBanner';
import { FeelingChips } from '../components/FeelingChips';
import { Icon } from '../components/Icon';
import { IntensityDials } from '../components/IntensityDial';
import { PatternEchoPanel } from '../components/PatternEchoPanel';
import { fetchInsights } from '../api/insights';
import type { EngineConstants, Entry, FeelingVocabulary, PatternEcho } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';
import { useUnsavedGuard } from '../hooks/useUnsavedGuard';

/**
 * View, edit and delete one entry (FR-006).
 *
 * Every mutation carries the `version` this screen loaded, so an edit or delete based on a view
 * that has gone stale is rejected rather than applied (FR-011/FR-021). A rejection hands off to
 * [ConflictView], which keeps the user's text on screen beside the stored version (FR-023) — the
 * text is never thrown away on their behalf.
 */
/**
 * Whether two rating maps say the same thing.
 *
 * Compared by content rather than by reference: the editor rebuilds the map on every keystroke of
 * a rating, and a reference check would report the entry as edited the moment anything was touched
 * and never report it as clean again.
 */
function sameIntensities(a: Record<string, number>, b: Record<string, number>): boolean {
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((key) => a[key] === b[key]);
}

export function EntryDetailScreen() {
  const { entryId = '' } = useParams();
  const navigate = useNavigate();

  const loaded = useRefreshable<Entry>(useCallback(() => getEntry(entryId), [entryId]));
  const { data: feelings } = useRefreshable<FeelingVocabulary>(
    useCallback(() => fetchFeelings(), []),
  );

  const [text, setText] = useState('');
  const [feelingKeys, setFeelingKeys] = useState<string[]>([]);
  // Keyed by feeling, so unpicking a word takes its rating with it rather than leaving a number
  // behind for whichever word lands in that position next.
  const [intensities, setIntensities] = useState<Record<string, number>>({});
  const [echoes, setEchoes] = useState<PatternEcho[]>([]);
  // The intensity scale is the backend's, like every other threshold this client renders. It is
  // read from the insights payload rather than assumed, so a change to the scale reaches both
  // clients at once (C-01).
  const [constants, setConstants] = useState<EngineConstants | null>(null);
  const [failure, setFailure] = useState<ApiFailure | null>(null);
  const [saving, setSaving] = useState(false);
  /** Set when a save/delete was rejected as stale. `current: null` = deleted elsewhere. */
  const [conflict, setConflict] = useState<{ mine: string; current: Entry | null } | null>(null);

  const entry = loaded.data;

  useEffect(() => {
    if (entry) {
      setText(entry.raw_text);
      setFeelingKeys(entry.feeling_keys);
      setIntensities(entry.feeling_intensities);
    }
  }, [entry]);

  useEffect(() => {
    void fetchInsights().then((result) => {
      if (result.ok) setConstants(result.value.constants);
    });
  }, []);

  // Compared as an ordered list, because the order is stored: moving a feeling to the front makes
  // it the entry's primary one, which is a real edit even though the set is unchanged.
  const dirty =
    entry !== null &&
    (text !== entry.raw_text ||
      !sameIntensities(intensities, entry.feeling_intensities) ||
      feelingKeys.length !== entry.feeling_keys.length ||
      feelingKeys.some((key, index) => key !== entry.feeling_keys[index]));
  const { confirmDiscard } = useUnsavedGuard(dirty);

  async function save(body: string, version: number) {
    setSaving(true);
    setFailure(null);

    const result = await updateEntry(entryId, {
      raw_text: body,
      feeling_keys: feelingKeys,
      feeling_intensities: intensities,
      version,
    });
    setSaving(false);

    if (result.ok) {
      // I4-02: the echo is asked for only once the entry is stored, and the user stays on the
      // screen to read it rather than being bounced away from their own observation.
      const echo = await fetchEntryEcho(entryId);
      if (echo.ok && echo.value.length > 0) {
        setEchoes(echo.value);
        loaded.refresh();
        return;
      }
      navigate('/app/today');
      return;
    }

    // FR-023: hand the rejection to the conflict view rather than dropping the user's text.
    if (result.error.kind === 'conflict') {
      setConflict({ mine: body, current: result.error.current ?? null });
      return;
    }
    // Deleted elsewhere: a PATCH gets 404, not 409 — there is no current version to compare
    // against (contracts/api.md). The writing is still preserved; only the actions differ.
    if (result.error.kind === 'not_found') {
      setConflict({ mine: body, current: null });
      return;
    }
    setFailure(result.error);
  }

  async function handleDelete() {
    if (!entry) return;
    if (!window.confirm('Delete this entry? This cannot be undone.')) return;

    setFailure(null);
    const result = await deleteEntry(entry.id, entry.version);
    if (result.ok) {
      navigate('/app/today');
      return;
    }
    // FR-021: a stale delete is refused. Show what the entry actually looks like now so the user
    // can decide again with current information.
    if (result.error.kind === 'conflict') {
      setConflict({ mine: text, current: result.error.current ?? null });
      return;
    }
    setFailure(result.error);
  }

  if (conflict) {
    return (
      <ConflictView
        mine={conflict.mine}
        current={conflict.current}
        onRetry={(mine, currentVersion) => {
          setConflict(null);
          void save(mine, currentVersion);
        }}
        onDiscard={() => navigate('/app/today')}
        onCarryAcross={(mine) => {
          // Put their words back in the editor against the now-current version, so they can merge
          // by hand. Nothing is combined automatically.
          setText(mine);
          setConflict(null);
          loaded.refresh();
        }}
      />
    );
  }

  if (loaded.loading)
    return (
      <p className="muted" role="status">
        Loading…
      </p>
    );
  if (!entry) {
    return (
      <div className="stack">
        <ErrorBanner failure={loaded.failure} onRetry={loaded.refresh} />
        <button type="button" className="btn btn--secondary" onClick={() => navigate('/app/today')}>
          <Icon name="chevronLeft" />
          Back to today
        </button>
      </div>
    );
  }

  return (
    <div className="stack stack--loose">
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">
            {new Date(entry.created_at).toLocaleString()}
          </span>
          <h1>Entry</h1>
        </div>
      </header>

      <ErrorBanner failure={failure} />

      <PatternEchoPanel echoes={echoes} onDismiss={() => setEchoes([])} />

      <label htmlFor="edit-text" className="visually-hidden">
        Entry text
      </label>
      <textarea
        id="edit-text"
        className="textarea"
        value={text}
        onChange={(e) => setText(e.target.value)}
      />

      <FeelingChips
        legend="Feelings"
        vocabulary={feelings}
        selected={feelingKeys}
        onChange={(keys) => {
          setFeelingKeys(keys);
          // A rating belongs to its feeling, so dropping a word drops its number too.
          setIntensities((current) =>
            Object.fromEntries(Object.entries(current).filter(([key]) => keys.includes(key))),
          );
        }}
        suggestedKeys={entry.suggested_feelings.map((suggestion) => suggestion.key)}
      />

      {/* I6-07: optional, after the feelings are chosen — never a step in front of them. */}
      {constants && (
        <IntensityDials
          // In the order the entry stores them, so the rows read in the same order as the chips.
          feelings={feelingKeys.flatMap(
            (key) => feelings?.feelings.filter((feeling) => feeling.key === key) ?? [],
          )}
          values={intensities}
          onChange={setIntensities}
          min={constants.min_intensity}
          max={constants.max_intensity}
        />
      )}

      {/*
        Delete is pushed to the opposite end of the row rather than sat third in a line of three.
        It is the one irreversible control on the screen, and putting it next to "Cancel" — which
        the hand reaches for to *avoid* changing anything — is how a diary entry gets lost.
      */}
      <div className="composer-actions">
        <button
          type="button"
          className="btn"
          onClick={() => void save(text, entry.version)}
          disabled={!dirty || saving}
        >
          {saving ? 'Saving…' : 'Save changes'}
          {!saving && <Icon name="check" />}
        </button>
        <button
          type="button"
          className="btn btn--secondary"
          onClick={() => {
            if (confirmDiscard()) navigate('/app/today');
          }}
        >
          Cancel
        </button>
        <button
          type="button"
          className="btn btn--danger composer-actions__aside"
          onClick={handleDelete}
        >
          <Icon name="trash" />
          Delete
        </button>
      </div>
    </div>
  );
}
