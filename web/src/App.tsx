import { useEffect, useState } from 'react';
import { NavLink, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { Icon } from './components/Icon';
import { EntryComposer } from './screens/EntryComposer';
import { EntryDetailScreen } from './screens/EntryDetailScreen';
import { InsightsScreen } from './screens/InsightsScreen';
import { MonthlyCalendarScreen } from './screens/MonthlyCalendarScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { TodayScreen } from './screens/TodayScreen';
import { TopicsScreen } from './screens/TopicsScreen';
import { initAppearance } from './hooks/useAppearance';

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

/*
 * Settings is last and stays last. The first four are places you go to read or write; the fifth is
 * where you go to change the app itself, which is a different kind of errand and belongs at the
 * end of the row rather than mixed in among them.
 */
const NAV = [
  { to: '/app/today', label: 'Today' },
  { to: '/app/insights', label: 'Insights' },
  { to: '/app/calendar', label: 'Calendar' },
  { to: '/app/topics', label: 'Topics' },
  { to: '/app/settings', label: 'Settings' },
];

export default function App() {
  const [authEnabled, setAuthEnabled] = useState(false);
  const { pathname } = useLocation();

  // Applies the stored palette/mode and keeps "System" honest if the OS flips while the tab is
  // open. index.html has already set the attributes before first paint; this is the live half.
  useEffect(() => initAppearance(), []);

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
        {/* Decorative: the nav's own accessible name comes from aria-label above. */}
        <span className="app-brand" aria-hidden="true">
          <span className="app-brand__mark">
            <Icon name="book" size="1.25em" />
          </span>
          <span className="app-brand__text">Mood diary</span>
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

      {/*
        The calendar is a seven-column grid rather than prose, so it gets the wider container. Every
        other screen stays at the reading measure — a diary entry stretched across a monitor is
        harder to read, not easier.
      */}
      <main
        className={`app-main${pathname.startsWith('/app/calendar') ? ' app-main--wide' : ''}`}
        id="main"
      >
        <Routes>
          <Route path="/" element={<Navigate to="/app/today" replace />} />
          <Route path="/app" element={<Navigate to="/app/today" replace />} />
          <Route path="/app/today" element={<TodayScreen />} />
          <Route path="/app/new" element={<EntryComposer />} />
          {/* Only the opaque UUID appears in the address — never entry text (FR-024). */}
          <Route path="/app/entry/:entryId" element={<EntryDetailScreen />} />
          <Route path="/app/insights" element={<InsightsScreen />} />
          <Route path="/app/calendar" element={<MonthlyCalendarScreen />} />
          <Route path="/app/topics" element={<TopicsScreen />} />
          <Route path="/app/settings" element={<SettingsScreen />} />
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
    <div className="empty-state">
      <span className="empty-state__icon">
        <Icon name="warning" size="1.5rem" />
      </span>
      <h1 className="empty-state__title">Not found</h1>
      <p>That page doesn&apos;t exist. It may have been a link to an entry that has since gone.</p>
      <NavLink to="/app/today" className="btn btn--secondary">
        Back to today
      </NavLink>
    </div>
  );
}
