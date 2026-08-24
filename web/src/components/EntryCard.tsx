import { Link } from 'react-router-dom';
import type { Entry, Feeling } from '../domain/types';

interface Props {
  entry: Entry;
  feelings: Feeling[];
}

function timeOf(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/**
 * One entry in a day's list. The whole card is a link to the entry's detail route, whose address
 * carries only the opaque UUID — never the text (FR-024).
 *
 * `data-feeling` on the root sets the `--feeling-color` custom property that tints both the card's
 * leading rail and the feeling label (see base.css). Doing it with one data attribute rather than
 * an inline style keeps the eight-way colour decision in the stylesheet, where the light and dark
 * variants already live.
 */
export function EntryCard({ entry, feelings }: Props) {
  const feeling = feelings.find((f) => f.key === entry.feeling_key) ?? null;
  const needsConfirming = entry.feeling_source === 'suggested';

  return (
    <Link
      to={`/app/entry/${entry.id}`}
      className="entry-card card"
      data-feeling={feeling?.key ?? undefined}
    >
      <div className="entry-card__head">
        <span className="entry-card__time tnum">{timeOf(entry.created_at)}</span>
        {feeling ? (
          <span className="row row--tight">
            <span className="entry-card__feeling">
              <span className="feeling-dot" aria-hidden="true" />
              {feeling.label}
            </span>
            {/*
              Spelled out rather than shown as a dot or a colour shift: "unconfirmed" is the
              difference between the app's guess and the user's own word, and that is not something
              to encode in a glyph.
            */}
            {needsConfirming && <span className="badge-hint">Unconfirmed</span>}
          </span>
        ) : (
          <span className="badge-hint">No feeling yet</span>
        )}
      </div>
      <p className="entry-card__text entry-card__text--clamped">{entry.raw_text}</p>
    </Link>
  );
}
