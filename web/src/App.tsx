import { useEffect, useState } from 'react';
import { NavLink, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { EntryComposer } from './screens/EntryComposer';
import { EntryDetailScreen } from './screens/EntryDetailScreen';
import { InsightsScreen } from './screens/InsightsScreen';
import { MonthlyCalendarScreen } from './screens/MonthlyCalendarScreen';
import { TodayScreen } from './screens/TodayScreen';

/**
 * The app shell and route table.
 *
 * Route addresses carry only view identity and opaque entry UUIDs — never entry text, guided
 * answers, or feelings (FR-024). Browser history syncs across devices on every major browser, so a
 * URL containing diary content would carry it off the LAN through a channel the no-authentication
 * threat model never accounted for.
 *
 * Everything is mounted under `/app` because the SPA's routes would otherwise collide with live API
 * paths (`/entries`, `/insights`), and re-prefixing the API would break the shipped Android app
 * (FR-018). See research.md §2.
 */

const NAV = [
  { to: '/app/today', label: 'Today' },
  { to: '/app/insights', label: 'Insights' },
  { to: '/app/calendar', label: 'Calendar' },
];

export default function App() {
  const [authEnabled, setAuthEnabled] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    void fetch('/auth/status', { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : null))
      .then((status: { enabled?: boolean } | null) => setAuthEnabled(status?.enabled === true))
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

  return (
    <div className="app-shell">
      <ScrollToTop />
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <nav className="app-nav" aria-label="Main">
        <span className="app-brand" aria-hidden="true">
          <span className="app-brand__mark">✦</span> Mood diary
        </span>
        {NAV.map(({ to, label }) => (
          <NavLink key={to} to={to}>
            {label}
          </NavLink>
        ))}
        {authEnabled && (
          <form className="app-nav__logout" method="post" action="/auth/logout">
            <button type="submit">Sign out</button>
          </form>
        )}
      </nav>

      <main className="app-main" id="main">
        <Routes>
          <Route path="/" element={<Navigate to="/app/today" replace />} />
          <Route path="/app" element={<Navigate to="/app/today" replace />} />
          <Route path="/app/today" element={<TodayScreen />} />
          <Route path="/app/new" element={<EntryComposer />} />
          {/* Only the opaque UUID appears in the address — never entry text (FR-024). */}
          <Route path="/app/entry/:entryId" element={<EntryDetailScreen />} />
          <Route path="/app/insights" element={<InsightsScreen />} />
          <Route path="/app/calendar" element={<MonthlyCalendarScreen />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
    </div>
  );
}

/** A client-side route change is a new screen; do not inherit a long editor/calendar scroll offset. */
function ScrollToTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo({ top: 0, left: 0 });
  }, [pathname]);
  return null;
}

function NotFound() {
  return (
    <div className="stack">
      <h1>Not found</h1>
      <p className="muted">That page doesn&apos;t exist.</p>
      <NavLink to="/app/today">Back to today</NavLink>
    </div>
  );
}
