import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/intensity_dial.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/journal_scrollbar.dart';
import '../../core/widgets/pattern_echo_panel.dart';
import 'entry_detail_controller.dart';

/// Matches one or more blank lines, the paragraph break in a freeform
/// entry's stored text.
final RegExp _paragraphBreak = RegExp(r'\n\s*\n');

/// View, edit and delete a single entry.
///
/// Reading is the default; editing is entered and left deliberately — the
/// screen used to open straight into a text field, which made reading back
/// what you wrote the same act as being one stray tap away from changing
/// it. The most delicate behaviour here is what happens when a save or
/// delete is refused because another device moved the entry on first: see
/// [EntryDetailController] and [_ConflictPanel].
class EntryDetailScreen extends ConsumerStatefulWidget {
  /// Creates the entry-detail screen for [entryId].
  ///
  /// [entryDate] is accepted only to match the fixed route shape
  /// (`/entry/:entryId/:entryDate`) — `getById` fetches by [entryId]
  /// alone, so this screen never parses [entryDate] and therefore never
  /// has a reason to throw on it, however it is spelled.
  ///
  /// [onClose] and [onDeleted] are plain callbacks rather than a direct
  /// `go_router` dependency, so this screen — and its tests — never need a
  /// router in the tree. Both default to popping the route.
  const EntryDetailScreen({
    super.key,
    required this.entryId,
    required this.entryDate,
    this.onClose,
    this.onDeleted,
  });

  /// The entry this screen shows.
  final String entryId;

  /// The day this entry was opened from, as `YYYY-MM-DD`.
  final String entryDate;

  /// Called when the user asks to leave this screen. Defaults to
  /// `Navigator.pop`.
  final VoidCallback? onClose;

  /// Called once the entry has actually been deleted. Defaults to
  /// `Navigator.pop`.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onClose case final onClose?) {
      onClose();
      return;
    }
    context.pop();
  }

  void _entryDeleted() {
    if (widget.onDeleted case final onDeleted?) {
      onDeleted();
      return;
    }
    context.pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      unawaited(
        ref
            .read(entryDetailControllerProvider(widget.entryId).notifier)
            .delete(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(
      entryDetailControllerProvider(widget.entryId).notifier,
    );

    ref.listen(entryDetailControllerProvider(widget.entryId), (previous, next) {
      if (next.deleted && (previous == null || !previous.deleted)) {
        _entryDeleted();
      }
    });

    ref.listen(entryDetailControllerProvider(widget.entryId), (previous, next) {
      final message = next.errorMessage;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      notifier.dismissError();
    });

    // Saving is confirmed the same way a failure is: one line at the
    // bottom of the screen, gone on its own. It never takes focus, so a
    // screen reader announces it without losing its place in the entry.
    ref.listen(entryDetailControllerProvider(widget.entryId), (previous, next) {
      final message = next.savedMessage;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      notifier.dismissSavedMessage();
    });

    final state = ref.watch(entryDetailControllerProvider(widget.entryId));
    final entry = state.entry;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          // In the editor, back means "leave the editor" rather than
          // "leave the entry": one gesture, one step out, so an
          // accidental tap never costs more than it looks like it will.
          onPressed: state.isEditing ? notifier.cancelEditing : _close,
          icon: const Icon(Icons.arrow_back),
          tooltip: state.isEditing ? 'Stop editing' : 'Back',
        ),
        actions: [
          if (!state.isEditing)
            IconButton(
              onPressed: entry == null ? null : notifier.startEditing,
              icon: const Icon(Icons.edit),
              tooltip: 'Edit entry',
            ),
          IconButton(
            onPressed: entry == null ? null : () => unawaited(_confirmDelete()),
            icon: const Icon(Icons.delete),
            tooltip: 'Delete entry',
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: switch (state) {
              // Before everything else: a refused change means the user
              // has a decision to make, and their words are being held
              // until they make it.
              EntryDetailState(conflict: final conflict?) => _ConflictPanel(
                conflict: conflict,
                onKeepMine: () => unawaited(notifier.retryWithCurrentVersion()),
                onDiscardMine: notifier.discardMine,
                onKeepEditing: notifier.carryMineAcross,
              ),
              EntryDetailState(hasLoaded: false) => const Center(
                child: CircularProgressIndicator(),
              ),
              EntryDetailState(entry: null) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('This entry is no longer available.'),
                ),
              ),
              EntryDetailState(isEditing: true) => _EntryEditor(
                state: state,
                scrollController: _scrollController,
                onTextChange: notifier.updateText,
                onFeelingsChange: notifier.updateFeelings,
                onIntensityChange: notifier.updateIntensity,
                onSave: () => unawaited(notifier.save()),
                onCancel: notifier.cancelEditing,
                onDismissEchoes: notifier.dismissEchoes,
              ),
              _ => _EntryReadView(
                entry: entry!,
                echoes: state.echoes,
                maxIntensity: state.constants.maxIntensity,
                scrollController: _scrollController,
                onEdit: notifier.startEditing,
                onDismissEchoes: notifier.dismissEchoes,
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// The entry as written, laid out to be read.
///
/// A guided entry is shown as the questions and answers it actually is,
/// each answer under the prompt it was answered against — using
/// [GuidedAnswer.questionText], the wording snapshot taken at the time, not
/// the library's current wording. The alternative, and what this screen
/// used to do, is print the stored [Entry.rawText]: for a guided entry that
/// is the same questions and answers run together into one unbroken block,
/// technically the entry and practically unreadable, because the reader
/// cannot tell where the app stopped asking and they started answering.
///
/// The stored text is still the fallback, and still what a freeform entry
/// shows, because a user is free to edit that text afterwards and what
/// they typed is then the truth about the entry. Blank lines in it are
/// honoured as paragraph breaks, not collapsed.
class _EntryReadView extends StatelessWidget {
  const _EntryReadView({
    required this.entry,
    required this.echoes,
    required this.maxIntensity,
    required this.scrollController,
    required this.onEdit,
    required this.onDismissEchoes,
  });

  final Entry entry;
  final List<PatternEcho> echoes;
  final int maxIntensity;
  final ScrollController scrollController;
  final VoidCallback onEdit;
  final VoidCallback onDismissEchoes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: JournalScrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                // Room for the bar to sit in, so it never lands on top of
                // a word.
                padding: const EdgeInsets.only(right: JournalSpacing.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.guidedAnswers.isNotEmpty)
                      for (var i = 0; i < entry.guidedAnswers.length; i++) ...[
                        if (i > 0) const SizedBox(height: JournalSpacing.x5),
                        Text(
                          entry.guidedAnswers[i].questionText,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: JournalSpacing.x2),
                        Text(
                          entry.guidedAnswers[i].answerText,
                          style: JournalType.prose,
                        ),
                      ]
                    else
                      for (final (i, paragraph) in _paragraphs(
                        entry.rawText,
                      ).indexed) ...[
                        if (i > 0) const SizedBox(height: JournalSpacing.x4),
                        Text(paragraph, style: JournalType.prose),
                      ],
                    if (entry.feelings.isNotEmpty) ...[
                      const SizedBox(height: JournalSpacing.x6),
                      const Eyebrow('Feelings'),
                      const SizedBox(height: JournalSpacing.x3),
                      _ReadOnlyFeelings(
                        feelings: entry.feelings,
                        intensities: entry.feelingIntensities,
                        maxIntensity: maxIntensity,
                      ),
                    ],
                    if (echoes.isNotEmpty) ...[
                      const SizedBox(height: JournalSpacing.x5),
                      PatternEchoPanel(
                        echoes: echoes,
                        onDismiss: onDismissEchoes,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: JournalSpacing.x4),
          SizedBox(
            width: double.infinity,
            child: SecondaryPillButton(
              onPressed: onEdit,
              child: const Text('Edit', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _paragraphs(String rawText) => [
  for (final paragraph in rawText.split(_paragraphBreak))
    if (paragraph.trim().isNotEmpty) paragraph.trim(),
];

/// The entry's feelings as stated, each with its rating when it has one.
///
/// Not chips that look tappable: nothing here is a control, and a control
/// that does nothing is worse than a label. The rating is spelled out
/// rather than drawn as a bar, because "3 of 5" is the whole answer and a
/// bar would need a legend to say the same thing.
class _ReadOnlyFeelings extends StatelessWidget {
  const _ReadOnlyFeelings({
    required this.feelings,
    required this.intensities,
    required this.maxIntensity,
  });

  final List<Feeling> feelings;
  final Map<String, int> intensities;
  final int maxIntensity;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    return Wrap(
      spacing: JournalSpacing.x2,
      runSpacing: JournalSpacing.x2,
      children: [
        for (final feeling in feelings)
          FeelingChip(
            label: feeling.label,
            color: feeling.accent(journal),
            intensityLabel: switch (intensities[feeling.key]) {
              null => null,
              final rating => '$rating of $maxIntensity',
            },
          ),
      ],
    );
  }
}

/// The entry open for editing: the text as stored, the feelings, and a
/// rating for each of them.
class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.state,
    required this.scrollController,
    required this.onTextChange,
    required this.onFeelingsChange,
    required this.onIntensityChange,
    required this.onSave,
    required this.onCancel,
    required this.onDismissEchoes,
  });

  final EntryDetailState state;
  final ScrollController scrollController;
  final ValueChanged<String> onTextChange;
  final ValueChanged<List<Feeling>> onFeelingsChange;
  final void Function(Feeling feeling, int? value) onIntensityChange;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onDismissEchoes;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.editedText,
  );

  @override
  void didUpdateWidget(covariant _EntryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the text changed for a reason other than this field's own
    // `onChanged` -- which already leaves `_controller.text` equal to
    // `editedText` -- so a keystroke never fights the cursor by resetting
    // the field to the value it just produced.
    if (widget.state.editedText != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.state.editedText,
        selection: TextSelection.collapsed(
          offset: widget.state.editedText.length,
        ),
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
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controller,
                    onChanged: widget.onTextChange,
                    minLines: 8,
                    maxLines: null,
                    style: JournalType.prose,
                    decoration: const InputDecoration(labelText: 'Entry text'),
                  ),
                  const SizedBox(height: JournalSpacing.x4),
                  const Eyebrow('Feelings'),
                  const SizedBox(height: JournalSpacing.x2),
                  FeelingChips(
                    groups: state.feelingGroups,
                    selected: state.editedFeelings,
                    onSelectionChange: widget.onFeelingsChange,
                    suggestedKeys: {
                      for (final suggestion
                          in state.entry?.suggestedFeelings ??
                              const <SuggestedFeeling>[])
                        suggestion.feeling.key,
                    },
                  ),
                  const SizedBox(height: JournalSpacing.x4),
                  // Optional, and after the feelings -- never before them.
                  IntensityDials(
                    feelings: state.editedFeelings,
                    intensities: state.editedIntensities,
                    onChange: widget.onIntensityChange,
                    min: state.constants.minIntensity,
                    max: state.constants.maxIntensity,
                  ),
                  if (state.echoes.isNotEmpty) ...[
                    const SizedBox(height: JournalSpacing.x4),
                    PatternEchoPanel(
                      echoes: state.echoes,
                      onDismiss: widget.onDismissEchoes,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: JournalSpacing.x4),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              onPressed: state.isSaving || state.editedText.trim().isEmpty
                  ? null
                  : widget.onSave,
              child: Text(
                state.isSaving ? 'Saving…' : 'Save changes',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
          TextButton(
            onPressed: state.isSaving ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Shown when a save or delete was refused because this screen's copy was
/// out of date.
///
/// Reject and preserve: `conflict.mine` — what the user wrote and tried to
/// save — stays on screen beside what is actually stored, and they choose.
/// There is deliberately no merge option; combining the two would produce
/// text they never wrote, which in a diary is worse than either version
/// winning outright.
class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({
    required this.conflict,
    required this.onKeepMine,
    required this.onDiscardMine,
    required this.onKeepEditing,
  });

  final EntryConflict conflict;
  final VoidCallback onKeepMine;
  final VoidCallback onDiscardMine;
  final VoidCallback onKeepEditing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This entry changed elsewhere',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'You edited this on another device since this screen loaded, so '
            "nothing was overwritten. Here's what you wrote and what's "
            'saved now.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          const Eyebrow('What you wrote'),
          const SizedBox(height: JournalSpacing.x2),
          JournalCard(child: Text(conflict.mine, style: JournalType.prose)),
          const SizedBox(height: JournalSpacing.x5),
          const Eyebrow("What's saved now"),
          const SizedBox(height: JournalSpacing.x2),
          JournalCard(
            child: Text(conflict.current.rawText, style: JournalType.prose),
          ),
          const SizedBox(height: JournalSpacing.x5),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              onPressed: onKeepMine,
              child: const Text('Keep mine (overwrite)'),
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
          SizedBox(
            width: double.infinity,
            child: SecondaryPillButton(
              onPressed: onKeepEditing,
              child: const Text('Keep editing mine'),
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onDiscardMine,
              child: const Text('Discard mine and use theirs'),
            ),
          ),
        ],
      ),
    );
  }
}
