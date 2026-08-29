import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../today/entry_card.dart';
import 'day_entries_controller.dart';

final DateFormat _dayTitleFormat = DateFormat('EEEE, MMMM d');
final DateFormat _timeFormat = DateFormat.jm();

/// A day with no time of day, expressed in whole days since the Unix epoch.
///
/// [PageView] pages by integer index; a diary entry pages by date. This is
/// the bijection between the two, so the controller can drive the page
/// beneath a swipe or a chevron tap with plain integer arithmetic instead of
/// re-deriving a date from a page offset by hand at every call site. UTC is
/// used purely as a fixed-length-day ruler -- every value here stays at
/// midnight, so daylight saving never enters into it the way it would if
/// this measured local instants instead.
final DateTime _epoch = DateTime.utc(1970);

/// The whole-day offset of [date] from the Unix epoch.
int _epochDay(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

/// The date [epochDay] whole days after the Unix epoch.
CalendarDate _dateFromEpochDay(int epochDay) =>
    CalendarDate.fromDateTime(_epoch.add(Duration(days: epochDay)));

/// The clock [DayEntriesScreen] reads "today" against, for the forward swipe
/// limit and the disabled next-day chevron.
///
/// Overridden in tests so which day counts as the swipe ceiling is
/// deterministic rather than following the real device clock — the same
/// reason [CalendarDate.today] itself takes an injectable `now`.
final dayEntriesNowProvider = Provider<DateTime?>((ref) => null);

/// Everything written on one day, readable end to end -- and every day
/// beside it one swipe away.
///
/// A day in the past is read to remember it. A heavy day used to mean an
/// endless scroll of full-length entries with no way to move on except
/// backing out to the calendar; entries are now truncated the same way
/// Today's feed truncates them, tapping one opens it in full, and a
/// horizontal swipe -- or the chevrons beside the date -- steps to the next
/// or previous day without leaving this screen. The quick "fix a typo and
/// let it re-read the feelings" edit stays here, inline, because that is a
/// different job from reading the entry in full: see [_DayEntryCard].
///
/// The [PageView] is the only thing that changes which day is showing;
/// nothing here ever pushes a second route while swiping or stepping, so
/// the back gesture always pops this one screen straight back to the
/// calendar, no matter how many days were swiped through first.
class DayEntriesScreen extends ConsumerStatefulWidget {
  /// Creates the day-entries screen, opening on [date].
  ///
  /// [date] arrives as a raw route parameter (`CalendarDate.toString()`)
  /// this screen does not control the shape of; an unparseable value falls
  /// back to today rather than throwing, the same rule every date-shaped
  /// route parameter in this app follows. A date after today is clamped to
  /// today, the same rule [DayEntriesScreen]'s swipe ceiling enforces for
  /// every later day too.
  ///
  /// [onClose] and [onOpenEntry] are plain callbacks rather than a direct
  /// `go_router` dependency, so this screen — and its tests — never need a
  /// router in the tree. [onClose] defaults to popping the route;
  /// [onOpenEntry] defaults to pushing the entry-detail route.
  const DayEntriesScreen({
    super.key,
    required this.date,
    this.onClose,
    this.onOpenEntry,
  });

  /// The day this screen opens on, as `YYYY-MM-DD`.
  final String date;

  /// Called when the user asks to leave this screen. Defaults to
  /// `Navigator.pop`.
  final VoidCallback? onClose;

  /// Called to open [Entry] in the entry-detail screen. Defaults to
  /// `context.push('/entry/{id}/{date}')`.
  final ValueChanged<Entry>? onOpenEntry;

  @override
  ConsumerState<DayEntriesScreen> createState() => _DayEntriesScreenState();
}

class _DayEntriesScreenState extends ConsumerState<DayEntriesScreen> {
  late CalendarDate _date;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final today = CalendarDate.today(now: ref.read(dayEntriesNowProvider));
    final parsed = CalendarDate.tryParse(widget.date) ?? today;
    _date = parsed > today ? today : parsed;
    _pageController = PageController(initialPage: _epochDay(_date));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onClose case final onClose?) {
      onClose();
      return;
    }
    context.pop();
  }

  void _openEntry(Entry entry) {
    if (widget.onOpenEntry case final onOpenEntry?) {
      onOpenEntry(entry);
      return;
    }
    context.push('/entry/${entry.id}/${entry.entryDate}');
  }

  void _stepTo(int page) {
    unawaited(
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = CalendarDate.today(now: ref.watch(dayEntriesNowProvider));
    final todayIndex = _epochDay(today);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Entries'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to the calendar',
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: PageView.builder(
              controller: _pageController,
              // Bounded at today: there is no tomorrow to read, so the
              // forward swipe simply runs out of pages rather than needing
              // its own resistance the way the drag in [TodayScreen] does.
              // Unbounded into the past -- a diary can hold entries from
              // any day it was started on.
              itemCount: todayIndex + 1,
              onPageChanged: (page) =>
                  setState(() => _date = _dateFromEpochDay(page)),
              itemBuilder: (context, page) {
                final pageDate = _dateFromEpochDay(page);
                return _DayEntriesPage(
                  date: pageDate,
                  onPreviousDay: () => _stepTo(page - 1),
                  onNextDay: page < todayIndex ? () => _stepTo(page + 1) : null,
                  onOpenEntry: _openEntry,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One day's worth of the [PageView]: the date header with its chevrons,
/// and that day's entries -- loaded and held entirely by
/// [dayEntriesControllerProvider], keyed on [date], so a page's data is
/// fetched only once it is actually built rather than for every day the
/// swipe ceiling allows.
class _DayEntriesPage extends ConsumerWidget {
  const _DayEntriesPage({
    required this.date,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onOpenEntry,
  });

  final CalendarDate date;
  final VoidCallback onPreviousDay;

  /// Steps to the next day, or `null` when [date] is already today -- the
  /// chevron's disabled state and the swipe ceiling agree because both
  /// answer the same question.
  final VoidCallback? onNextDay;
  final ValueChanged<Entry> onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(dayEntriesControllerProvider(date), (previous, next) {
      final message = next.errorMessage;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      ref.read(dayEntriesControllerProvider(date).notifier).dismissError();
    });

    final state = ref.watch(dayEntriesControllerProvider(date));
    final notifier = ref.read(dayEntriesControllerProvider(date).notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        JournalSpacing.x4,
        JournalSpacing.x2,
        JournalSpacing.x4,
        JournalSpacing.x7,
      ),
      children: [
        PageHeader(
          eyebrow: Eyebrow(_dayTitleFormat.format(date.toDateTime())),
          title: Text(
            state.entries.length == 1
                ? '1 entry'
                : '${state.entries.length} entries',
            style: theme.textTheme.headlineSmall,
          ),
          actions: [
            _DayStepButton(
              onPressed: onPreviousDay,
              description: 'Previous day',
              icon: Icons.chevron_left,
            ),
            _DayStepButton(
              onPressed: onNextDay,
              description: 'Next day',
              icon: Icons.chevron_right,
            ),
          ],
        ),
        const SizedBox(height: JournalSpacing.x4),
        if (state.isAnalysing) ...[
          const _AnalysingNotice(),
          const SizedBox(height: JournalSpacing.x3),
        ],
        if (state.proposal case final proposal?) ...[
          _FeelingProposalCard(
            feelings: proposal.feelings,
            onAccept: () => unawaited(notifier.acceptProposal()),
            onDismiss: notifier.dismissProposal,
          ),
          const SizedBox(height: JournalSpacing.x3),
        ],
        if (!state.hasLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: JournalSpacing.x7),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.entries.isEmpty)
          EmptyState(
            icon: const Icon(Icons.edit_note),
            title: const Text('Nothing written that day'),
            supporting: const Text(
              'Days without entries stay blank — nothing was lost.',
              textAlign: TextAlign.center,
            ),
            // Backdating (#36): this day always had entries it could have
            // held, so the empty state offers a way to add one instead of
            // only explaining the blank.
            action: PillButton(
              onPressed: () => context.push('/compose?date=$date'),
              child: const Text('Write about this day'),
            ),
          )
        else
          for (final entry in state.entries) ...[
            _DayEntryCard(
              // Keyed on the entry's id so a save (which reorders nothing
              // but does replace the list with a freshly fetched one) never
              // hands this card's own text-field state to a different entry
              // landing at the same position.
              key: ValueKey(entry.id),
              entry: entry,
              isEditing: state.editingId == entry.id,
              draft: state.draft,
              isSaving: state.isSaving,
              onEdit: () => notifier.startEditing(entry),
              onDraftChange: notifier.updateDraft,
              onSave: () => unawaited(notifier.saveEdit()),
              onCancel: notifier.cancelEditing,
              onOpenDetail: () => onOpenEntry(entry),
            ),
            const SizedBox(height: JournalSpacing.x3),
          ],
      ],
    );
  }
}

/// One step of the day stepper: a 48dp bounded icon button, sized for a
/// thumb rather than the icon -- the same touch target the Today screen's
/// own day stepper uses.
class _DayStepButton extends StatelessWidget {
  const _DayStepButton({
    required this.onPressed,
    required this.description,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: JournalSpacing.x7,
    height: JournalSpacing.x7,
    child: Semantics(
      label: description,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: Icon(icon),
        ),
      ),
    ),
  );
}

class _AnalysingNotice extends StatelessWidget {
  const _AnalysingNotice();

  @override
  Widget build(BuildContext context) => JournalCard(
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: JournalSpacing.x3),
        Text(
          'Re-reading that entry…',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.journalColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// The analyser's proposal after an edit.
///
/// Framed as a question with an explicit "keep" option rather than as a
/// notification with a dismiss: the feeling on an entry may have been
/// chosen deliberately, and re-reading the words is not grounds for
/// overruling that quietly. Accepting is the only thing on this screen that
/// changes an entry's feelings.
class _FeelingProposalCard extends StatelessWidget {
  const _FeelingProposalCard({
    required this.feelings,
    required this.onAccept,
    required this.onDismiss,
  });

  final List<Feeling> feelings;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final phrase = _joinToPhrase([
      for (final feeling in feelings) feeling.label.toLowerCase(),
    ]);

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('After that edit'),
          const SizedBox(height: JournalSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final feeling in feelings) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: 6,
                    right: JournalSpacing.x1,
                  ),
                  child: _Dot(color: feeling.accent(journal)),
                ),
              ],
              const SizedBox(width: JournalSpacing.x1),
              Expanded(
                child: Text(
                  'This now reads more like $phrase.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x4),
          Row(
            children: [
              PillButton(onPressed: onAccept, child: Text('Use $phrase')),
              const SizedBox(width: JournalSpacing.x2),
              SecondaryPillButton(
                onPressed: onDismiss,
                child: const Text('Keep as is'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `[a]` -> "a"; `[a, b]` -> "a and b"; `[a, b, c]` -> "a, b and c".
String _joinToPhrase(List<String> words) => switch (words.length) {
  0 => '',
  1 => words.single,
  _ => '${words.take(words.length - 1).join(', ')} and ${words.last}',
};

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// One entry in the day's list.
///
/// Reading and editing are two different jobs, and this card offers both
/// without conflating them. At rest it is the same truncated, tappable
/// [EntryCard] the Today feed shows -- six lines here rather than five,
/// because a full day's worth of entries has more competing for the screen
/// than Today's single day does -- and tapping it opens the entry in full
/// on the entry-detail screen, feelings, ratings and delete included.
/// "Edit text" underneath stays a separate, narrower action: a quick fix to
/// a typo, saved in place, that the backend then re-reads and may propose
/// new feelings for -- see [DayEntriesController.saveEdit]. That re-analysis
/// offer has no equivalent on the entry-detail screen, so it stays here
/// rather than moving with the rest of editing.
class _DayEntryCard extends StatefulWidget {
  const _DayEntryCard({
    super.key,
    required this.entry,
    required this.isEditing,
    required this.draft,
    required this.isSaving,
    required this.onEdit,
    required this.onDraftChange,
    required this.onSave,
    required this.onCancel,
    required this.onOpenDetail,
  });

  final Entry entry;
  final bool isEditing;
  final String draft;
  final bool isSaving;
  final VoidCallback onEdit;
  final ValueChanged<String> onDraftChange;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onOpenDetail;

  @override
  State<_DayEntryCard> createState() => _DayEntryCardState();
}

class _DayEntryCardState extends State<_DayEntryCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft,
  );

  @override
  void didUpdateWidget(covariant _DayEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the draft changed for a reason other than this field's own
    // `onChanged` -- which already leaves `_controller.text` equal to
    // `widget.draft` -- so a keystroke never fights the cursor position by
    // resetting the field to the value it just produced.
    if (widget.draft != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.draft,
        selection: TextSelection.collapsed(offset: widget.draft.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isSaving = widget.isSaving;

    if (!widget.isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntryCard(entry: entry, onTap: widget.onOpenDetail, maxLines: 6),
          const SizedBox(height: JournalSpacing.x2),
          SecondaryPillButton(
            onPressed: widget.onEdit,
            child: const Text('Edit text'),
          ),
        ],
      );
    }

    final journal = context.journalColors;
    final theme = Theme.of(context);
    final railColor = entry.feeling?.accent(journal) ?? journal.hairline;
    final shape = JournalShapes.large;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: journal.hairline),
        borderRadius: shape,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: railColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(JournalSpacing.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            right: JournalSpacing.x2,
                          ),
                          child: Eyebrow(
                            _timeFormat.format(entry.createdAt.toLocal()),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: JournalSpacing.x2,
                            runSpacing: JournalSpacing.x1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final feeling in entry.feelings)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Dot(color: feeling.accent(journal)),
                                    const SizedBox(width: JournalSpacing.x2),
                                    Text(
                                      feeling.label,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: feeling.accent(journal),
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: JournalSpacing.x3),
                    TextField(
                      controller: _controller,
                      onChanged: widget.onDraftChange,
                      minLines: 4,
                      maxLines: null,
                      style: JournalType.prose,
                    ),
                    const SizedBox(height: JournalSpacing.x3),
                    Row(
                      children: [
                        PillButton(
                          onPressed: isSaving ? null : widget.onSave,
                          child: Text(isSaving ? 'Saving…' : 'Save'),
                        ),
                        const SizedBox(width: JournalSpacing.x2),
                        SecondaryPillButton(
                          onPressed: isSaving ? null : widget.onCancel,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
