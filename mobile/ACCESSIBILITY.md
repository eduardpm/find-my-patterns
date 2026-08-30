# Accessibility conventions

Short, concrete rules this app's screens already follow, written down so the
next screen follows them too rather than reinventing (or missing) them. Not a
tutorial on accessibility in general — just this codebase's own answers to the
questions that came up while auditing every screen for #150 (semantics,
dynamic type, touch targets).

## 1. Stating a number in words

A stat surface — a bar, a count, a rating — carries two things: the visual
(bars, digits, dots) and one spoken sentence that says the same fact in
words. The spoken sentence is not a narration of the widget tree; it is
written the way a person would say the fact out loud.

**Pattern:** wrap the whole stat in one `Semantics(container: true, label:
spoken)`, then `ExcludeSemantics` its visual children so a screen reader
stops at the sentence instead of also reading every digit and label
underneath it one at a time.

```dart
Semantics(
  container: true,
  label: spoken, // "The day so far. 3 entries, 7:15 AM – 10:40 PM. Happy,
                 //  Calm. Strongest: Happy 4/5, plus 1 more at the same
                 //  rating." -- today/day_summary_card.dart
  child: ExcludeSemantics(child: /* the bars, dots, digits */),
);
```

Real examples already in the codebase:

- `lib/features/today/day_summary_card.dart` — the whole card's spoken
  description, built as one `StringBuffer`.
- `lib/features/insights/pattern_card.dart`'s `_barSentence` — "With
  walking: calm in 3 of 6 entries, 50 percent" for each strength bar, and
  `_confounderSplitSentence` for the 2×2 confounder split once expanded.
- `lib/features/calendar/calendar_screen.dart`'s `_spokenLabel` — a day
  cell's whole story in one sentence: `"5, 2 entries, Happy, Sad,
  intensity 4"`, or `"6, no entries"` outright (never left implied).
- `lib/core/widgets/intensity_dial.dart`'s `_IntensityStop` — `"Grateful, 3
  of 5"`, named per feeling since more than one row of stops can share a
  screen.

**Count and pluralise correctly, every time.** `count == 1 ? 'entry' :
'entries'`, not a bare `'$count entries'` — the plural-only form reads as
"1 entries" on a real diary once a count is exactly one, and this bug
recurred twice in this codebase (`withdrawal_notice.dart`, `pattern_card.dart`
evidence toggle) before this ticket. `digest_screen.dart`, `when_panel.dart`
and `pattern_card.dart`'s own `_footerText` already get this right — match
their branch, don't invent a new one.

## 2. Icon-only controls need a real `label`, not just a `tooltip`

`IconButton(tooltip: 'X')` does **not** give a screen reader an accessible
name. `IconButton`'s own semantics node sets `button: true` and nothing
else; `tooltip` only ever reaches the separate `SemanticsData.tooltip`
field (via the `Tooltip` widget wrapping the icon), which a screen reader
does not announce as the control's name. Every icon-only button —
chevrons, a close "×", a back arrow, a collapsed FAB — needs an explicit
outer `Semantics` with its own `label`:

```dart
Semantics(
  container: true,
  button: true,
  label: 'Dismiss', // the same string the tooltip carries, for sighted
                     // hover/long-press users
  onTap: onDismiss,
  child: ExcludeSemantics(
    child: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Dismiss', // keep both -- this is not a replacement for
                           // tooltip, it is what tooltip alone cannot do
      onPressed: onDismiss,
    ),
  ),
);
```

`enabled:` and a conditional `label:`/`onTap:` carry through the same way
for a button whose action or availability changes (see
`entry_detail_screen.dart`'s back button, which reads "Back" or "Stop
editing" depending on whether the editor is open).

A `FloatingActionButton` that collapses to just its icon needs the same
treatment on the `Icon` itself once its label is no longer visible:

```dart
Icon(Icons.add, semanticLabel: _expanded ? null : fabLabel)
```

— see `today/today_screen.dart`'s FAB.

Test this with `find.bySemanticsLabel('X')`, not `find.byTooltip('X')`.
`byTooltip` only proves the tooltip string is right; it does not prove a
screen reader can find the button by name.

**A bare `Semantics(label: ...)` sibling can silently merge into its
neighbours' node.** Several small `Semantics`-labelled widgets sitting
side by side inside one `ListView` item (or any other single semantics
node an ancestor already scopes) do not automatically get their own
node each — without `container: true`, Flutter merges every descendant
label upward into one aggregate string ("Monday\nTuesday\n...\nSunday"
instead of seven separate "Monday", "Tuesday", ... nodes), and
`find.bySemanticsLabel('Monday')` then finds nothing even though the
word is right there in the tree. `_MonthSwitcher`'s two chevrons already
needed `container: true` for the same reason (`calendar_screen.dart`);
`_WeekdayHeaderRow`'s per-column `Semantics` (#155) is the same fix for
plain labelled text, not just icon buttons. Debug this with
`debugDumpSemanticsTree()` rather than guessing from the widget tree —
the merge is invisible in `flutter analyze`, in `find.byType`, and in a
`Semantics.label` read off the widget itself; it only shows up once the
tree is actually built and the accessibility layer has merged it.

## 3. Dynamic type: measure, don't guess

Every screen is checked at **320dp width, textScale 1.3 and 2.0** — the
narrowest phone this app treats as real, and the accessibility ceiling
several existing tests already use. `tester.view.physicalSize`,
`tester.view.devicePixelRatio = 1`, and a `TextScaler` set via `.copyWith`
on the *ambient* `MediaQuery` (see the pitfall below) reproduce this in a
widget test without a device.

**A row overflows when its non-flexible content no longer fits its own
line — never assume a fixed number of characters is "safe."** Seven
instances of this exact bug family shipped before anyone wrote a
geometry-based test for it (#108, #111, #115, #117, #131, #137, #141; #150
added an eighth — the calendar month grid's own day cells overflowed a
320dp/2x screen by up to 64px, every cell in the month at once). The fix
is always one of:

- **Wrap a label, don't truncate or shrink it.** `Flexible(child: Text(...))`
  around whichever sibling is not the load-bearing number/identifier — see
  `_MonthSwitcher`'s month name, `_TotalsPanel`'s "entries a day" label,
  `StatusBadge`'s own internal label (`core/widgets/journal.dart`),
  `_ModeOptionContent`'s mode label (`settings/appearance_card.dart`). This
  app never truncates a number or a name a person needs to read in full.
- **`Wrap`, not `Row`, for a fixed number of fixed-size items that might not
  share one line** — `IntensityDials`' 5-stop row, `FeelingChips`' chip
  rows. Each item keeps its full size; extra items flow to a new line
  instead of shrinking or overflowing.
- **Measure the real rendered geometry at the real `TextStyle`/`TextScaler`
  when a hard threshold would be wrong.** `TextPainter(text: ...,
  textScaler: MediaQuery.textScalerOf(context))..layout()` asks the exact
  question a `LayoutBuilder` needs answered — "does this fit *this* width,
  right now" — instead of guessing from a hardcoded scale or character
  count. See `today/day_summary_card.dart`'s `_measure` (width) and
  `calendar/calendar_screen.dart`'s `_measureHeight` (height, and note
  that a measurement must use the same `maxWidth` the real widget will be
  given — an *unbounded* measurement misses that real text can wrap,
  which undercounted a day cell's needed height by a full line the first
  time this fix was written).

**Pitfall: `MediaQuery(data: MediaQueryData(textScaler: ...))` discards
every other ambient field**, including `size` and `padding`. Always
`.copyWith` the *ambient* data instead:

```dart
Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(2),
    ),
    child: ...,
  ),
)
```

A bare `MediaQueryData(textScaler: ...)` can silently zero out a
simulated status-bar inset a test means to check (this is exactly how
#150's status-bar defect was first missed, then caught once the test was
fixed to use `.copyWith`).

**What a green test must actually prove.** `expect(tester.takeException(),
isNull)` catches an overflow, but it also passes trivially on a tree that
rendered nothing at all — always pair it with a positive assertion that the
content in question actually rendered (`find.text(...)`,
`find.bySemanticsLabel(...)`, or a `tester.getSize`/`getRect` check).
`find.byType`/`find.byWidgetPredicate` alone prove a widget exists in the
tree, never that it painted at a non-zero size — assert with
`tester.getSize`/`getTopLeft`/`getRect` for anything about rendered
geometry. And when a new test is meant to catch a specific defect, prove
it does: revert the fix, watch the test fail for the right reason, then
restore the fix.

**On `test/support/rendered_text.dart`:** left as-is, not widened into a
general geometry helper. It solves one specific problem — a string that
can legitimately be carried by either a plain `Text` or a `Text.rich`
depending on which layout branch a row took — and every defect this
ticket found and fixed was a geometry problem (`RenderFlex` overflow, an
undersized touch target, a missing semantics label), not a
which-widget-shape-carried-this-string problem. `tester.takeException()`
paired with a positive content check, plus targeted `tester.getSize`/
`getTopLeft`, already covers everything this ticket's own fixes needed;
inventing a shared wrapper for that now would be speculative rather than
demand-driven.

**A row of near-identical siblings needs one shared fit decision, not
seven independent ones.** `calendar_screen.dart`'s weekday header (#155)
renders seven short labels of otherwise-equal width ("Mo", "Tu", "We",
...) across seven equal columns, and at 320dp/2x only "MO" — "M" being
the widest capital in the set — no longer fit its column and wrapped
onto a second line while its six siblings stayed on one: a ragged,
two-line-tall header, not an overflow (nothing threw). Letting each
column decide independently whether *it* fits (the naive per-column
`FittedBox`/wrap) fixes the overflow but produces a *different*
inconsistency — the one column that had to shrink now looks visually
smaller, or is the only one on two lines, than its neighbours. The fix
measures the *widest* label once against the real per-column width and
lets that single yes/no decision drive every column identically, so all
seven either keep their normal form or all seven drop to a shorter one
together. Any row of siblings that are supposed to look uniform (a
header, a legend, a row of short badges) should make this decision once
and apply it everywhere, not per-item.

## 4. Touch targets: ≥44×44, verified by measurement

The Material minimum (this codebase uses 48dp, `JournalSpacing.x7`) is the
floor for anything tappable, however small its icon or label is drawn:
chips' remove "×", intensity circles, chevrons. Two ways this has actually
been undersized in practice:

- **An explicit `constraints:` override with no minimum at all.**
  `IconButton(constraints: const BoxConstraints())` removes the platform's
  own 48dp default outright — set an explicit `BoxConstraints(minWidth:
  JournalSpacing.x7, minHeight: JournalSpacing.x7)` instead of an empty
  one.
- **`visualDensity: VisualDensity.compact` fighting an explicit
  `constraints:` floor.** Compact density subtracts a fixed amount from
  *whatever* constraints it is handed, `minWidth`/`minHeight` included —
  it can silently undercut a floor set right next to it. Drop `compact`
  density on anything that also needs to hold a hard minimum.

Verify with `tester.getSize(finder)`, not by reading the constructor
arguments — a `Container`'s stated `constraints` can still be overridden
downstream (`visualDensity`, an ancestor's own tighter constraints) before
paint.

## 5. Decorative icons

An icon that repeats what an adjacent label or the control's own
`Semantics.label` already says is decorative and stays out of the tree —
either it sits inside a subtree already wrapped in `ExcludeSemantics` (the
common case: every icon-only button pattern in §2 above), or, if it needs
to stay reachable individually for some other reason, wrap it directly in
`ExcludeSemantics`. Never give a purely decorative icon its own
`Semantics.label` — that produces a second, redundant stop a screen reader
has to sit through for information it already has.

## 6. The whole-app layout sweep

Sections 3 and 4 tell you how to measure one screen. `test/screen_layout_matrix_test.dart`
measures **all of them**, so that a screen nobody has audited is no longer a
screen with no coverage.

Before it, dynamic-type coverage was opt-in: seventeen hand-written per-screen
tests out of forty-six widget-bearing files, each added by whichever ticket
happened to be looking at that screen — and nothing said which screens were
still unmeasured. Eighteen instances of one layout bug family shipped that way.

It checks three invariants, at 320/360dp × textScale 1.0/1.3/2.0. Only the
first is the classic:

1. **Nothing throws.** A `RenderFlex` overflow, which
   `expect(tester.takeException(), isNull)` already catches.
2. **No text paints outside the screen horizontally.** Silent. #164's extended
   `FloatingActionButton` rendered off *both* edges without throwing, because
   `FloatingActionButton.extended` fixes its height and leaves its width
   unconstrained.
3. **No single-word label is broken across lines while the screen had room.**
   Silent. A fixed-width sibling starves an `Expanded`/`Wrap`, and since a
   `Wrap` cannot split one child in two, the child's own label breaks mid-word
   instead — "Relaxed" rendered as "Relaxe"/"d" in `entry_card.dart` (#168),
   which needed 196px and was given 43.5px.

Invariants 2 and 3 exist because the family's failure mode moved: it is no
longer only "the test asserted the widget tree rather than the render", it is
now also "**the test's own harness was more generous than the real screen**".
`pattern_card.dart`'s dynamic-type test passes while the card overflows in the
real `InsightsScreen` (#163), because its harness gives the card more width
than the screen's padding leaves it.

**These are invariants, not layout assertions.** `CONSTITUTION.md` Article 3
rules out asserting pixel positions, and rightly — a test pinning a label to
x=16 breaks on every visual tweak. These assert only that text renders
*somewhere inside the screen* and that words are not broken in half. No
legitimate visual change can break them.

### Adding a screen

Register a `ScreenCase` in that file. The `every widget file is accounted for`
guard walks `lib/` and fails when a widget file is neither registered, nor
covered by its own `TextScaler` test, nor named in `kUnsweptSurfaces` — so a
new screen cannot be added without someone deciding which it is. That list is
the visible backlog: shrinking it is the work, and it must never grow.

A cell that fails for a defect you are not fixing goes in `knownFailures` with
its issue number, which shows up in the test name — a known defect stays
visible rather than disappearing the way an unwritten test does.
