import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fetchMonthlySummary } from '../src/api/monthlySummary';
import { MonthlyCalendarScreen } from '../src/screens/MonthlyCalendarScreen';
import type { MonthlySummary } from '../src/domain/types';

vi.mock('../src/api/monthlySummary', () => ({ fetchMonthlySummary: vi.fn() }));

const fetchMock = vi.mocked(fetchMonthlySummary);

/**
 * Deliberately booby-trapped: if the screen ever re-tallies `days` instead of rendering the
 * server's numbers, these assertions fail.
 *
 * The trap is real, not artificial. `days[].feelings` is the *distinct* set of feelings on a day
 * (see backend/app/services/summary_service.py), so a client-side sum would count "happy" twice
 * here, not nine times — and the average divides by days *elapsed*, which the client cannot see.
 *
 *   summed from days:  happy 2, sleepy 1, neutral 1  → total 4 feelings over 4 listed days = 1.0/day
 *   served by backend: happy 9, sleepy 4, neutral 2  → 1.4285714285714286 per day
 */
const SERVED: MonthlySummary = {
  month: '2026-05',
  days: [
    { date: '2026-05-01', feelings: ['happy'] },
    { date: '2026-05-02', feelings: ['sleepy', 'neutral'] },
    { date: '2026-05-03', feelings: [] },
    { date: '2026-05-04', feelings: ['happy'] },
  ],
  totals_by_feeling: { happy: 9, sleepy: 4, neutral: 2 },
  average_entries_per_day: 1.4285714285714286,
};

function ok(summary: MonthlySummary) {
  return { ok: true as const, value: summary };
}

function totalsRow(label: string): HTMLElement {
  const row = screen.getByText(label).closest('li');
  if (!row) throw new Error(`No totals row found for "${label}"`);
  return row;
}

beforeEach(() => {
  fetchMock.mockReset();
  fetchMock.mockResolvedValue(ok(SERVED));
});

describe('MonthlyCalendarScreen — served numbers, never recomputed (Principle VII, SC-005)', () => {
  it('renders each per-feeling total exactly as returned, not as summed from the day cells', async () => {
    render(<MonthlyCalendarScreen />);
    await screen.findByRole('heading', { name: 'This month' });

    expect(within(totalsRow('Happy')).getByText('9')).toBeInTheDocument();
    expect(within(totalsRow('Sleepy')).getByText('4')).toBeInTheDocument();
    expect(within(totalsRow('Neutral')).getByText('2')).toBeInTheDocument();

    // The counts a re-tallying client would have produced from `days` must appear nowhere.
    expect(within(totalsRow('Happy')).queryByText('2')).toBeNull();
    expect(within(totalsRow('Sleepy')).queryByText('1')).toBeNull();
    expect(within(totalsRow('Neutral')).queryByText('1')).toBeNull();
  });

  it('renders the served daily average, never a recomputed one', async () => {
    render(<MonthlyCalendarScreen />);

    // The served 1.4285714285714286, shown to one decimal to match Android's `%.1f` (SC-005 wants
    // both clients to display the *same* number, and rounding for display is presentation).
    expect(await screen.findByText('1.4')).toBeInTheDocument();

    const totals = screen.getByRole('region', { name: 'This month' });
    // The naive client-side answer — 4 feelings ÷ 4 listed days — must appear nowhere. Rounding
    // can't hide a recomputation here: 1.4 and 1.0 stay distinguishable at one decimal.
    expect(within(totals).queryByText('1.0')).toBeNull();
    expect(within(totals).queryByText('1')).toBeNull();
  });

  it('shows totals for feelings that appear in no day cell at all', async () => {
    // A month whose entries all lost their feeling assignment on the day level would still have
    // month totals. The client must not filter totals against `days`.
    fetchMock.mockResolvedValue(
      ok({
        month: '2026-05',
        days: [{ date: '2026-05-01', feelings: [] }],
        totals_by_feeling: { stressed: 6 },
        average_entries_per_day: 0.2,
      }),
    );

    render(<MonthlyCalendarScreen />);
    await screen.findByRole('heading', { name: 'This month' });

    expect(within(totalsRow('Stressed')).getByText('6')).toBeInTheDocument();
    expect(screen.getByText('0.2')).toBeInTheDocument();
  });

  it('re-renders the newly served numbers when the month changes, still verbatim', async () => {
    const user = userEvent.setup();
    render(<MonthlyCalendarScreen />);
    await screen.findByText('1.4');

    const firstMonth = fetchMock.mock.calls[0][0];
    expect(firstMonth).toMatch(/^\d{4}-(0[1-9]|1[0-2])$/);

    fetchMock.mockResolvedValue(
      ok({
        month: 'previous',
        days: [{ date: '2026-04-01', feelings: ['happy'] }],
        totals_by_feeling: { happy: 31 },
        average_entries_per_day: 2.93,
      }),
    );
    await user.click(screen.getByRole('button', { name: 'Previous month' }));

    // 2.93 served, displayed as 2.9 — still unmistakably the server's number, not a re-tally.
    expect(await screen.findByText('2.9')).toBeInTheDocument();
    expect(within(totalsRow('Happy')).getByText('31')).toBeInTheDocument();
    expect(within(totalsRow('Happy')).queryByText('9')).toBeNull();

    const previousMonth = fetchMock.mock.calls[1][0];
    expect(previousMonth).not.toBe(firstMonth);
    expect(previousMonth).toMatch(/^\d{4}-(0[1-9]|1[0-2])$/);

    // Previous then Next must land back where it started — the only month logic on the client.
    await user.click(screen.getByRole('button', { name: 'Next month' }));
    expect(fetchMock.mock.calls[2][0]).toBe(firstMonth);
  });
});

describe('CalendarGrid day cells (US5 AC1/AC3/AC4)', () => {
  it('shows one dot per feeling on a multi-feeling day and names them in text', async () => {
    render(<MonthlyCalendarScreen />);
    await screen.findByRole('heading', { name: 'This month' });

    // Regex rather than a literal date string: the month name is locale-formatted.
    const multiFeelingDay = screen.getByText(/^2 .+: Sleepy, Neutral$/);
    const cell = multiFeelingDay.closest('td');
    expect(cell).toHaveClass('calendar-day--logged');
    expect(cell?.querySelectorAll('.calendar-day__dot')).toHaveLength(2);
  });

  it('marks days with no entries distinguishably, and not by colour alone', async () => {
    render(<MonthlyCalendarScreen />);
    await screen.findByRole('heading', { name: 'This month' });

    const emptyDay = screen.getByText(/^3 .+: no entries$/).closest('td');
    expect(emptyDay).toHaveClass('calendar-day--empty');
    expect(emptyDay?.querySelectorAll('.calendar-day__dot')).toHaveLength(0);

    const loggedDay = screen.getByText(/^1 .+: Happy$/).closest('td');
    expect(loggedDay).toHaveClass('calendar-day--logged');
  });

  it('lays the first day of the month out under its real weekday column', async () => {
    render(<MonthlyCalendarScreen />);
    await screen.findByRole('heading', { name: 'This month' });

    // 2026-05-01 is a Friday: in a Monday-first grid that is the 5th column, so four blanks first.
    const firstWeek = screen.getAllByRole('row')[1];
    const cells = within(firstWeek).getAllByRole('cell');
    expect(cells.slice(0, 4).every((cell) => cell.className === 'calendar-day--outside')).toBe(
      true,
    );
    expect(within(cells[4]).getByText(/^1 .+: Happy$/)).toBeInTheDocument();
  });
});
