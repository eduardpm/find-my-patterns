import { Link } from 'react-router-dom';
import { resolveFeelings } from '../api/feelings';
import type { Entry, FeelingVocabulary } from '../domain/types';

interface Props {
  entry: Entry;
  vocabulary: FeelingVocabulary | null;
}

function timeOf(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/**
 * One entry in a day's list. The whole card is a link to the entry's detail route, whose address
 * carries only the opaque UUID — never the text (FR-024).
 *
 * `data-feeling-group` on the root sets the `--feeling-color` custom property that tints both the
 * card's leading rail and the feeling labels (see base.css). Doing it with one data attribute
 * rather than an inline style keeps the colour decision in the stylesheet, where the light and dark
 * variants already live.
 *
 * An entry can carry several feelings, and every one of them is named. The rail takes the primary
 * feeling's colour — a card has one edge, and picking the first feeling is the same rule the
 * backend already applies to `feeling_key` rather than a second one invented here.
 */
export function EntryCard({ entry, vocabulary }: Props) {
  const feelings = resolveFeelings(vocabulary, entry.feeling_keys);
  const primary = feelings[0] ?? null;
  const needsConfirming = entry.feeling_source === 'suggested';

  return (
    <Link
      to={`/app/entry/${entry.id}`}
      className="entry-card card"
      data-feeling-group={primary?.group_key ?? undefined}
    >
      <div className="entry-card__head">
        <span className="entry-card__time tnum">{timeOf(entry.created_at)}</span>
        {/* The row wraps: an entry can carry up to four feelings, and a non-wrapping row would
            push the last of them off the card's edge. */}
        {feelings.length > 0 ? (
          <span className="row">
            {feelings.map((feeling) => (
              <span
                key={feeling.key}
                className="entry-card__feeling"
                data-feeling-group={feeling.group_key}
              >
                <span className="feeling-dot" aria-hidden="true" />
                {feeling.label}
              </span>
            ))}
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
