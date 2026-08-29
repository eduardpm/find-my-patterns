import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { PatternCard } from '../src/components/PatternCard';
import { WhenPanel } from '../src/components/WhenPanel';
import { WithdrawalNotice } from '../src/components/WithdrawalNotice';
import type { EngineConstants, Pattern, WhenInsights, Withdrawal } from '../src/domain/types';

/**
 * What the new insight surfaces put on screen (roadmap A1, A2, A3, I1, I2, I3, I5).
 *
 * Every assertion here is that the client *renders what it was given* — constitution Principle VII.
 * There is deliberately no test that the client computed a rate, ranked a pattern, or decided a
 * label, because doing any of those would be the defect. The counterpart assertions on the backend
 * live in `backend/tests/e2e/roadmap-engine.test.ts`, against the same payload shape.
 */

const CONSTANTS: EngineConstants = {
  min_occurrence_threshold: 3,
  recency_window_days: 30,
  min_lift: 1.5,
  strong_lift: 3,
  strong_min_occurrences: 5,
  min_comparison_entries: 3,
  collinearity_threshold: 0.8,
  min_bucket_entries: 3,
  min_intensity: 1,
  max_intensity: 5,
};

const pattern = (overrides: Partial<Pattern> = {}): Pattern => ({
  id: 'p1',
  kind: 'forward',
  topic: 'meetings',
  feeling: 'anxious',
  occurrence_count: 8,
  lifetime_count: 20,
  status: 'active',
  direction: 'change',
  narrative_text:
    'You felt anxious in 8 of 12 entries mentioning meetings in the last 30 days (67%), and in 3 of 28 entries without it (11%).',
  suggestion_text: 'Pay attention to how meetings affects your anxious feeling.',
  present_count: 8,
  present_total: 12,
  absent_count: 3,
  absent_total: 28,
  present_rate: 8 / 12,
  absent_rate: 3 / 28,
  base_rate: 0.275,
  lift: 6.222222,
  comparison_reason: null,
  comparison_note: null,
  is_strong: true,
  last_occurrence_date: '2026-08-25',
  days_since_last_occurrence: 1,
  historical_note: null,
  confounders: [],
  evidence: Array.from({ length: 8 }, (_, index) => ({
    entry_id: `e${index}`,
    entry_date: `2026-08-${String(10 + index).padStart(2, '0')}`,
    raw_text: `Back to back meetings, day ${index + 1}.`,
    feeling_keys: ['anxious'],
    feeling_source: 'confirmed' as const,
  })),
  last_updated_at: '2026-08-26T09:00:00.000000',
  // R-1: additive and null for almost every pattern — see `PatternRecommendation` in
  // `src/domain/types.ts`. No surface here renders it yet (that is mobile's work), so the fixture
  // just needs a value that type-checks.
  recommendation: null,
  ...overrides,
});

const renderCard = (value: Pattern) =>
  render(
    <MemoryRouter>
      <PatternCard pattern={value} constants={CONSTANTS} />
    </MemoryRouter>,
  );

describe('PatternCard — the numbers behind the claim (A3)', () => {
  it('shows both rates, the base rate and the lift as served', () => {
    renderCard(pattern());
    expect(screen.getByText('67%')).toBeInTheDocument();
    expect(screen.getByText('11%')).toBeInTheDocument();
    expect(screen.getByText('28%')).toBeInTheDocument(); // the base rate
    expect(screen.getByText('6.2×')).toBeInTheDocument();
    expect(screen.getByText('8/12')).toBeInTheDocument();
  });

  it('prints an em dash rather than a number when the lift could not be computed (A3-02)', () => {
    renderCard(
      pattern({
        lift: null,
        comparison_reason: 'insufficient_comparison',
        comparison_note: 'Not enough entries without meetings to compare.',
        is_strong: false,
      }),
    );
    // A "0.0×" here would turn "we could not compare" into "there is no association".
    expect(screen.queryByText(/0\.0×/)).not.toBeInTheDocument();
    expect(screen.getByText('Not enough entries without meetings to compare.')).toBeInTheDocument();
  });

  it('marks a strong pattern in words, not by colour alone (A3-07, FR-027)', () => {
    renderCard(pattern());
    expect(screen.getByText('Strong')).toBeInTheDocument();
  });
});

describe('PatternCard — the evidence trail (A1)', () => {
  it('opens the supporting entries from the card itself, in the order sent (A1-04/A1-05)', async () => {
    const user = userEvent.setup();
    renderCard(pattern());

    // A1-02: the button's count is the pattern's own count, because they are the same fact.
    const toggle = screen.getByRole('button', { name: /show the 8 entries/i });
    await user.click(toggle);

    const rows = screen.getAllByRole('listitem');
    const dates = rows.map((row) => within(row).getByText(/2026-08-\d\d/).textContent);
    expect(dates).toEqual([...dates].sort());
    // A1-06: each one opens in the normal entry flow.
    expect(screen.getAllByRole('link')[0]).toHaveAttribute('href', '/app/entry/e0');
  });

  it('explains an empty trail on a historical pattern rather than showing nothing (I3-06)', async () => {
    const user = userEvent.setup();
    renderCard(
      pattern({
        status: 'historical',
        occurrence_count: 0,
        evidence: [],
        historical_note: 'Last seen 62 days ago. 5 occurrences across your whole diary.',
        comparison_note: 'Nothing in the last 30 days to compare — this pattern is historical.',
      }),
    );
    expect(screen.getByText('Historical')).toBeInTheDocument();
    expect(
      screen.getByText('Last seen 62 days ago. 5 occurrences across your whole diary.'),
    ).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /show the 0 entries/i }));
    expect(screen.getByText(/built on older entries/i)).toBeInTheDocument();
  });
});

describe('PatternCard — the other direction and the caveats (I1, I2)', () => {
  it('labels an inverse card in words and swaps which side each rate describes (I1-03)', () => {
    renderCard(
      pattern({
        kind: 'inverse',
        topic: 'exercise',
        feeling: 'sad',
        direction: 'keep',
        narrative_text: 'You felt sad in 4 of 10 entries without exercise…',
      }),
    );
    expect(screen.getByText('Without it')).toBeInTheDocument();
    expect(screen.getByText('Without exercise')).toBeInTheDocument();
    expect(screen.getByText('With exercise')).toBeInTheDocument();
    expect(screen.getByText('Worth keeping')).toBeInTheDocument();
  });

  it('annotates a confounded pattern without hiding it (I2-07)', () => {
    renderCard(
      pattern({
        confounders: [
          {
            topic: 'coffee',
            co_occurrence_rate: 0.9,
            both_count: 9,
            only_this_count: 1,
            only_other_count: 2,
            neither_count: 8,
            inseparable: false,
            note: 'meetings and coffee appear together in 9 of 10 entries mentioning meetings (90%).',
          },
        ],
      }),
    );
    expect(screen.getByText(/appear together in 9 of 10/)).toBeInTheDocument();
    // Still a full card: the narrative and the figures are all still there.
    expect(screen.getByText('6.2×')).toBeInTheDocument();
  });
});

describe('PatternCard — no badge for a neutral-valence pattern (P0-2)', () => {
  // A neutral-valence feeling has no positive signal to reinforce and no negative one to
  // discourage, so the backend sends `direction: 'none'` and this card shows neither badge —
  // never falling back to "Worth changing", which was the defect P0-2 fixes (a card reading
  // "consider changing" a feeling that was fine). Mirrors
  // `mobile/test/features/insights/pattern_card_test.dart`'s equivalent case.
  it('renders no badge and no pattern-badge element at all', () => {
    const { container } = renderCard(pattern({ direction: 'none' }));
    expect(screen.queryByText('Worth keeping')).not.toBeInTheDocument();
    expect(screen.queryByText('Worth changing')).not.toBeInTheDocument();
    expect(container.querySelector('.pattern-badge')).toBeNull();
  });

  it('still shows every other figure on the card untouched', () => {
    renderCard(pattern({ direction: 'none' }));
    expect(screen.getByText('67%')).toBeInTheDocument();
    expect(screen.getByText('6.2×')).toBeInTheDocument();
  });

  // P0-6: a badge-less card carries no tip strip either — the same rule applies whether the
  // reason is a neutral valence (here) or an undefined lift (its own describe block below).
  it('shows no suggestion strip either, since there is no badge to back it', () => {
    renderCard(pattern({ direction: 'none' }));
    expect(screen.queryByText(/pay attention to how meetings affects/i)).not.toBeInTheDocument();
  });
});

describe('PatternCard — no badge for an undefined or below-threshold lift (P0-6)', () => {
  // The exact bug reported live: "Work → anxious" showed `LIFT —` (0 of 7 entries without work,
  // a division by zero) and still carried a red "Worth changing" badge — advice built on the one
  // number the card itself prints as a dash. The backend now folds this into `direction: 'none'`
  // (see `badgeDirectionFor` in `backend/src/insights/patterns.service.ts`), and this client reads
  // that value unchanged, same as it already did for P0-2's neutral-valence case.
  it('shows no badge and no suggestion strip for a card whose lift is undefined', () => {
    const { container } = renderCard(
      pattern({
        topic: 'work',
        feeling: 'anxious',
        direction: 'none',
        lift: null,
        comparison_reason: 'no_absent_occurrences',
        comparison_note:
          'This feeling does not appear in any entry without work, so there is no ratio to state.',
        present_count: 4,
        present_total: 4,
        absent_count: 0,
        absent_total: 7,
        present_rate: 1,
        absent_rate: 0,
        is_strong: false,
      }),
    );

    expect(screen.queryByText('Worth keeping')).not.toBeInTheDocument();
    expect(screen.queryByText('Worth changing')).not.toBeInTheDocument();
    expect(container.querySelector('.pattern-badge')).toBeNull();
    expect(screen.queryByText(/pay attention to how meetings affects/i)).not.toBeInTheDocument();

    // The card's counts and explanation still stand — honesty stays.
    expect(screen.getByText('4/4')).toBeInTheDocument();
    expect(screen.getByText('0/7')).toBeInTheDocument();
    expect(
      screen.getByText(
        'This feeling does not appear in any entry without work, so there is no ratio to state.',
      ),
    ).toBeInTheDocument();
    // A "0.0×" here would turn "the ratio could not be computed" into "there is no association".
    expect(screen.queryByText(/0\.0×/)).not.toBeInTheDocument();
  });

  // The other half of the same rule: a lift that clears the minimum keeps its badge, per P0-2's
  // mapping — P0-6 only withholds the badge when the lift itself gives it nothing to stand on.
  it('keeps its badge and suggestion strip when the lift clears the minimum', () => {
    renderCard(pattern({ direction: 'change', lift: 6.222222 }));
    expect(screen.getByText('Worth changing')).toBeInTheDocument();
    expect(screen.getByText(/pay attention to how meetings affects/i)).toBeInTheDocument();
  });
});

describe('WithdrawalNotice (A2)', () => {
  const withdrawal: Withdrawal = {
    id: 'w1',
    topic: 'tea',
    feeling: 'calm',
    kind: 'forward',
    previous_count: 3,
    new_count: 2,
    reason: 'below_threshold',
    detail_text: 'tea → calm was withdrawn: 3 occurrences, now 2 — below the minimum of 3.',
    withdrawn_at: '2026-08-26T09:00:00.000000',
    is_new: true,
  };

  it('states the previous count, the new one, and the reason', () => {
    render(
      <ul>
        <WithdrawalNotice withdrawal={withdrawal} />
      </ul>,
    );
    expect(screen.getByText(withdrawal.detail_text)).toBeInTheDocument();
    expect(screen.getByText('3 → 2')).toBeInTheDocument();
    expect(screen.getByText('Not enough left')).toBeInTheDocument();
  });

  it('names a weakened association separately from thinned-out evidence (A2-02)', () => {
    // The two are different things that happened to the user's diary, and the badge is the only
    // place a reader sees which. "Not enough left" beside 12 → 12 would be false.
    render(
      <ul>
        <WithdrawalNotice
          withdrawal={{
            ...withdrawal,
            reason: 'below_lift',
            previous_count: 12,
            new_count: 12,
            detail_text:
              'without reading → anxious was withdrawn: still 12 occurrences, but the association is no longer stronger than your usual rate by the minimum of 1.5×.',
          }}
        />
      </ul>,
    );
    expect(screen.getByText('Association too weak')).toBeInTheDocument();
    expect(screen.queryByText('Not enough left')).not.toBeInTheDocument();
  });

  it('says "without" for an inverse pattern, which is what it was a claim about', () => {
    render(
      <ul>
        <WithdrawalNotice withdrawal={{ ...withdrawal, kind: 'inverse', topic: 'exercise' }} />
      </ul>,
    );
    expect(screen.getByText('Without exercise')).toBeInTheDocument();
  });
});

describe('WhenPanel (I5)', () => {
  const insights: WhenInsights = {
    window_days: 30,
    min_bucket_entries: 3,
    total_entries: 20,
    weekdays: [
      {
        key: 'monday',
        label: 'Monday',
        entry_count: 5,
        average_valence: -0.6,
        negative_rate: 0.8,
        sufficient: true,
      },
      {
        key: 'tuesday',
        label: 'Tuesday',
        entry_count: 1,
        average_valence: null,
        negative_rate: null,
        sufficient: false,
      },
      {
        key: 'saturday',
        label: 'Saturday',
        entry_count: 6,
        average_valence: 0.7,
        negative_rate: 0.1,
        sufficient: true,
      },
    ],
    times_of_day: [],
    best_weekday: 'saturday',
    worst_weekday: 'monday',
    best_time_of_day: null,
    worst_time_of_day: null,
  };

  it('names the best and worst buckets in words as well as by position (I5-05)', () => {
    render(<WhenPanel insights={insights} />);
    expect(screen.getByText('Best')).toBeInTheDocument();
    expect(screen.getByText('Hardest')).toBeInTheDocument();
  });

  it('reports a thin bucket as insufficient rather than as an average (I5-02)', () => {
    render(<WhenPanel insights={insights} />);
    expect(screen.getByText(/fewer than 3 entries/)).toBeInTheDocument();
    // A marker at zero would read as a perfectly ordinary Tuesday.
    expect(screen.queryByText('+0.00')).not.toBeInTheDocument();
  });

  it('says these are times rather than causes (I5-06)', () => {
    render(<WhenPanel insights={insights} />);
    expect(screen.getByText(/times, not causes/)).toBeInTheDocument();
  });
});
