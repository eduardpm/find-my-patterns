import { Link } from 'react-router-dom';
import type { Entry, Feeling } from '../domain/types';

interface Props {
  entry: Entry;
  feelings: Feeling[];
}

const EMOJI: Record<string, string> = {
  happy: '😊',
  excited: '🤩',
  neutral: '😐',
  sleepy: '😴',
  exhausted: '🥱',
  stressed: '😖',
  sad: '😢',
  depressed: '😞',
};

function timeOf(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/**
 * One entry in a day's list. The whole card is a link to the entry's detail route, whose address
 * carries only the opaque UUID — never the text (FR-024).
 */
export function EntryCard({ entry, feelings }: Props) {
  const feeling = feelings.find((f) => f.key === entry.feeling_key) ?? null;
  const needsConfirming = entry.feeling_source === 'suggested';

  return (
    <Link to={`/app/entry/${entry.id}`} className="entry-card card">
      <div className="entry-card__head">
        <span className="muted">{timeOf(entry.created_at)}</span>
        {feeling ? (
          <span className="entry-card__feeling" data-feeling={feeling.key}>
            <span aria-hidden="true">{EMOJI[feeling.key] ?? '•'}</span> {feeling.label}
            {needsConfirming && <span className="chip__hint"> · unconfirmed</span>}
          </span>
        ) : (
          <span className="muted">No feeling yet</span>
        )}
      </div>
      <p className="entry-card__text">{entry.raw_text}</p>
    </Link>
  );
}
