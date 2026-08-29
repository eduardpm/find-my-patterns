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
import 'day_entries_controller.dart';

final DateFormat _dayTitleFormat = DateFormat('EEEE, MMMM d');
final DateFormat _timeFormat = DateFormat.jm();

/// Everything written on one day, readable end to end and editable in
/// place — text only, by design.
///
/// A day in the past is read to remember it, and the useful edit is fixing
/// what was said, not re-running the guided prompts, which describe the
/// moment of writing rather than the day itself. Saving sends only the
/// text; what the re-analysis then proposes is offered, never applied — see
/// [_FeelingProposalCard].
class DayEntriesScreen extends ConsumerWidget {
  /// Creates the day-entries screen for [date].
  ///
  /// [date] arrives as a raw route parameter (`CalendarDate.toString()`)
  /// this screen does not control the shape of; an unparseable value falls
  /// back to today rather than throwing, the same rule every date-shaped
  /// route parameter in this app follows.
  ///
  /// [onClose] is a plain callback rather than a direct `go_router`
  /// dependency, so this screen — and its tests — never need a router in
  /// the tree. Defaults to popping the route.
  const DayEntriesScreen({super.key, required this.date, this.onClose});

  /// The day this screen shows, as `YYYY-MM-DD`.
  final String date;

  /// Called when the user asks to leave this screen. Defaults to
  /// `Navigator.pop`.
  final VoidCallback? onClose;

  void _close(BuildContext context) {
    if (onClose case final onClose?) {
      onClose();
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedDate = CalendarDate.tryParse(date) ?? CalendarDate.today();

    ref.listen(dayEntriesControllerProvider(resolvedDate), (previous, next) {
      final message = next.errorMessage;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      ref
          .read(dayEntriesControllerProvider(resolvedDate).notifier)
          .dismissError();
    });

    final state = ref.watch(dayEntriesControllerProvider(resolvedDate));
    final notifier = ref.read(
      dayEntriesControllerProvider(resolvedDate).notifier,
    );
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Entries'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => _close(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to the calendar',
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                JournalSpacing.x4,
                JournalSpacing.x2,
                JournalSpacing.x4,
                JournalSpacing.x7,
              ),
              children: [
                Eyebrow(_dayTitleFormat.format(resolvedDate.toDateTime())),
                const SizedBox(height: JournalSpacing.x1),
                Text(
                  state.entries.length == 1
                      ? '1 entry'
                      : '${state.entries.length} entries',
                  style: theme.textTheme.headlineSmall,
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
                  const EmptyState(
                    icon: Icon(Icons.edit_note),
                    title: Text('Nothing written that day'),
                    supporting: Text(
                      'Days without entries stay blank — nothing was lost.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final entry in state.entries) ...[
                    _DayEntryCard(
                      // Keyed on the entry's id so a save (which reorders
                      // nothing but does replace the list with a freshly
                      // fetched one) never hands this card's own text-field
                      // state to a different entry landing at the same
                      // position.
                      key: ValueKey(entry.id),
                      entry: entry,
                      isEditing: state.editingId == entry.id,
                      draft: state.draft,
                      isSaving: state.isSaving,
                      onEdit: () => notifier.startEditing(entry),
                      onDraftChange: notifier.updateDraft,
                      onSave: () => unawaited(notifier.saveEdit()),
                      onCancel: notifier.cancelEditing,
                    ),
                    const SizedBox(height: JournalSpacing.x3),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  });

  final Entry entry;
  final bool isEditing;
  final String draft;
  final bool isSaving;
  final VoidCallback onEdit;
  final ValueChanged<String> onDraftChange;
  final VoidCallback onSave;
  final VoidCallback onCancel;

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
    final isEditing = widget.isEditing;
    final isSaving = widget.isSaving;
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
                    if (isEditing) ...[
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
                    ] else ...[
                      Text(entry.rawText, style: JournalType.prose),
                      const SizedBox(height: JournalSpacing.x3),
                      SecondaryPillButton(
                        onPressed: widget.onEdit,
                        child: const Text('Edit text'),
                      ),
                    ],
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
