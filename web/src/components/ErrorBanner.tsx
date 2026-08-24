import type { ApiFailure } from '../api/client';

interface Props {
  failure: ApiFailure | null;
  onRetry?: () => void;
}

/**
 * The single place a failed request becomes visible (FR-013). The app must never appear to have
 * saved something it didn't, so this is deliberately loud: an alert role, so it is announced to
 * assistive tech (FR-027), and never auto-dismissing.
 */
export function ErrorBanner({ failure, onRetry }: Props) {
  if (!failure) return null;

  return (
    <div className="error-banner" role="alert">
      <span>{failure.message}</span>
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
