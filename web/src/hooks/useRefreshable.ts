import { useCallback, useEffect, useState } from 'react';
import type { ApiFailure, ApiResult } from '../api/client';

interface Refreshable<T> {
  data: T | null;
  failure: ApiFailure | null;
  loading: boolean;
  /** FR-019: the explicit refresh the user can rely on. */
  refresh: () => void;
}

/**
 * Loads data once and exposes a manual refresh.
 *
 * There is deliberately no polling and no persistent connection here. FR-019 rules out live updates
 * for v1, and a push channel for a single-user app is the speculative generality constitution
 * Principle II forbids. The cost of a stale view is bounded instead by the conflict protection in
 * FR-011/FR-023 — which is why acting on stale data is safe even though seeing it is possible.
 */
export function useRefreshable<T>(load: () => Promise<ApiResult<T>>): Refreshable<T> {
  const [data, setData] = useState<T | null>(null);
  const [failure, setFailure] = useState<ApiFailure | null>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);

  const refresh = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    load().then((result) => {
      if (cancelled) return;
      if (result.ok) {
        setData(result.value);
        setFailure(null);
      } else {
        setFailure(result.error);
      }
      setLoading(false);
    });

    return () => {
      cancelled = true;
    };
    // `load` is expected to be stable (module-level fn or useCallback); `nonce` drives refreshes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nonce]);

  return { data, failure, loading, refresh };
}
