import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import type { ApiFailure } from '../api/client';
import { deleteEntry, getEntry, updateEntry } from '../api/entries';
import { ConflictView } from './ConflictScreen';
import { fetchFeelings } from '../api/feelings';
import { ErrorBanner } from '../components/ErrorBanner';
import { FeelingChips } from '../components/FeelingChips';
import type { Entry, Feeling } from '../domain/types';
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
export function EntryDetailScreen() {
  const { entryId = '' } = useParams();
  const navigate = useNavigate();

  const loaded = useRefreshable<Entry>(useCallback(() => getEntry(entryId), [entryId]));
  const { data: feelings } = useRefreshable<Feeling[]>(useCallback(() => fetchFeelings(), []));

  const [text, setText] = useState('');
  const [feelingKey, setFeelingKey] = useState<string | null>(null);
  const [failure, setFailure] = useState<ApiFailure | null>(null);
  const [saving, setSaving] = useState(false);
  /** Set when a save/delete was rejected as stale. `current: null` = deleted elsewhere. */
  const [conflict, setConflict] = useState<{ mine: string; current: Entry | null } | null>(null);

  const entry = loaded.data;

  useEffect(() => {
    if (entry) {
      setText(entry.raw_text);
      setFeelingKey(entry.feeling_key);
    }
  }, [entry]);

  const dirty = entry !== null && (text !== entry.raw_text || feelingKey !== entry.feeling_key);
  const { confirmDiscard } = useUnsavedGuard(dirty);

  async function save(body: string, version: number) {
    setSaving(true);
    setFailure(null);

    const result = await updateEntry(entryId, {
      raw_text: body,
      feeling_key: feelingKey ?? undefined,
      version,
    });
    setSaving(false);

    if (result.ok) {
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

  if (loaded.loading) return <p className="muted">Loading…</p>;
  if (!entry) {
    return (
      <div className="stack">
        <ErrorBanner failure={loaded.failure} onRetry={loaded.refresh} />
        <button type="button" className="btn btn--text" onClick={() => navigate('/app/today')}>
          Back to today
        </button>
      </div>
    );
  }

  return (
    <div className="stack">
      <div className="app-header">
        <h1>Entry</h1>
        <span className="muted">{new Date(entry.created_at).toLocaleString()}</span>
      </div>

      <ErrorBanner failure={failure} />

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
        legend="Feeling"
        feelings={feelings ?? []}
        selected={feelingKey}
        onSelect={setFeelingKey}
      />

      <div className="row">
        <button
          type="button"
          className="btn"
          onClick={() => void save(text, entry.version)}
          disabled={!dirty || saving}
        >
          {saving ? 'Saving…' : 'Save changes'}
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
        <button type="button" className="btn btn--danger" onClick={handleDelete}>
          Delete
        </button>
      </div>
    </div>
  );
}
