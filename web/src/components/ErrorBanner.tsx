import type { ApiFailure } from '../api/client';
import { Icon } from './Icon';

interface Props {
  failure: ApiFailure | null;
  onRetry?: () => void;
}

/**
 * The single place a failed request becomes visible (FR-013). The app must never appear to have
 * saved something it didn't, so this is deliberately loud: an alert role, so it is announced to
 * assistive tech (FR-027), and never auto-dismissing.
 *
 * The warning icon is decorative — it repeats what the border colour and the message already say —
 * so it stays out of the accessibility tree. It earns its place for sighted users who need the
 * banner to read as an error at a glance rather than as a tinted box (FR-027 forbids relying on
 * colour alone for that distinction).
 */
export function ErrorBanner({ failure, onRetry }: Props) {
  if (!failure) return null;

  return (
    <div className="error-banner" role="alert">
      <Icon name="warning" className="icon error-banner__icon" />
      <span className="error-banner__message">{failure.message}</span>
      {failure.kind === 'unauthorized' && (
        <a className="btn btn--text" href="/login?next=/app/today">
          Sign in
        </a>
      )}
      {onRetry && (
        <button type="button" className="btn btn--text" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}
