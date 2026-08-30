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
