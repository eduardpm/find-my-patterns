import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/topic.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/status_views.dart';
import 'topics_controller.dart';

/// The topics the diary has found, and the words the user has taught it to
/// fold into them.
///
/// Topic normalisation has a half the backend cannot decide alone. The
/// canonical list handles what is true for everyone — a project review is
/// work — and this screen handles what is true for one person: "gym
/// session" is exercise in most diaries and something else entirely in a
/// physiotherapist's. The alternative was asking a model whether two phrases
/// mean the same thing, which is exactly the judgement this project keeps it
/// out of. Everything added here takes effect on the next recompute: no
/// model runs, and no entry changes.
class TopicsScreen extends ConsumerWidget {
  /// Creates the Topics screen.
  ///
  /// [onClose] is a plain callback rather than a direct `go_router`
  /// dependency, so this screen — and its tests — never need a router in the
  /// tree: the caller decides what "back" means.
  const TopicsScreen({super.key, required this.onClose});

  /// Called when the user asks to leave this screen.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // A failed add or remove must not replace the list on screen — the user's
    // aliases are still there, only the edit did not take. So the failure is
    // shown once, as a SnackBar, and immediately cleared from the state that
    // produced it rather than left to reappear on the next rebuild.
    ref.listen(topicsControllerProvider, (previous, next) {
      final message = next.value?.errorMessage;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      ref.read(topicsControllerProvider.notifier).dismissError();
    });

    final async = ref.watch(topicsControllerProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(
                left: JournalSpacing.x4,
                right: JournalSpacing.x4,
                top: JournalSpacing.x5,
                bottom: JournalSpacing.x7,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: JournalSpacing.x2),
                    Expanded(
                      child: PageHeader(
                        eyebrow: const Eyebrow('What the diary noticed'),
                        title: Text(
                          'Topics',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: JournalSpacing.x3),
                Text(
                  'Add another way you write about a topic and the two are '
                  'counted as one from the next time Insights is opened.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: JournalSpacing.x3),
                ..._content(context, async),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, AsyncValue<TopicsState> async) {
    if (!async.hasValue) return const [LoadingView()];

    final topics = async.requireValue.topics;
    if (topics.isEmpty) {
      final theme = Theme.of(context);
      return [
        EmptyState(
          icon: const Icon(Icons.label_outline),
          title: Text('No topics yet', style: theme.textTheme.titleLarge),
          supporting: Text(
            'Topics appear once you have written entries the app can read '
            'them from.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    return [
      for (final topic in _byEntryCountDescending(topics)) ...[
        // Keyed on the topic's id, not its position: without this, removing
        // or reordering a topic would hand this element's leftover draft
        // controller and expanded/collapsed state to whatever topic now
        // lands at the same index.
        _TopicRow(key: ValueKey(topic.id), topic: topic),
        const SizedBox(height: JournalSpacing.x2),
      ],
    ];
  }
}

/// Orders [topics] by [TopicDetail.entryCount], most-noticed first.
///
/// A plain `List.sort` is not guaranteed stable in Dart, and two topics with
/// the same count should not visibly swap places every time the list
/// happens to be rebuilt. Sorting a list of `(topic, index)` pairs and
/// falling back to the original index keeps ties in the order the backend
/// sent them, without pulling in a collection package for one stable sort.
List<TopicDetail> _byEntryCountDescending(List<TopicDetail> topics) {
  final indexed =
      [
        for (var i = 0; i < topics.length; i++) (topic: topics[i], index: i),
      ]..sort((a, b) {
        final byCount = b.topic.entryCount.compareTo(a.topic.entryCount);
        return byCount != 0 ? byCount : a.index.compareTo(b.index);
      });
  return [for (final entry in indexed) entry.topic];
}

/// One topic as a compact row: its name, entry count, and existing aliases
/// as small chips. Tapping the row expands it in place to reveal the field
/// for teaching it a new alias and, while open, a way to remove an existing
/// one.
///
/// Collapsed by default and keyed on [TopicDetail.id] by its caller, so a
/// diary with dozens of topics reads as a scannable list rather than a wall
/// of identical empty text fields — and so removing or reordering a topic
/// never hands this row's expanded state or draft controller to a different
/// topic that happens to land at the same list position.
///
/// A [ConsumerStatefulWidget] rather than a stateless one because both the
/// expanded/collapsed flag and the draft alias are per-row, ephemeral UI
/// state that has no business living in [TopicsController].
class _TopicRow extends ConsumerStatefulWidget {
  const _TopicRow({super.key, required this.topic});

  final TopicDetail topic;

  @override
  ConsumerState<_TopicRow> createState() => _TopicRowState();
}

class _TopicRowState extends ConsumerState<_TopicRow> {
  final TextEditingController _draft = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final alias = _draft.text.trim();
    if (alias.isEmpty) return;
    final added = await ref
        .read(topicsControllerProvider.notifier)
        .addAlias(widget.topic.id, alias);
    // The draft only resets once the backend has accepted it — a rejected
    // alias stays on screen for the user to fix rather than vanishing along
    // with what they typed.
    if (added && mounted) _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = widget.topic;
    final notifier = ref.read(topicsControllerProvider.notifier);
    final entryCountLabel =
        '${topic.entryCount} ${topic.entryCount == 1 ? 'entry' : 'entries'}';

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: '${_capitalize(topic.name)}, $entryCountLabel',
            expanded: _expanded,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                // 48dp: the touch-target floor, since the row is otherwise
                // only as tall as a line of text.
                constraints: const BoxConstraints(minHeight: JournalSpacing.x7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _capitalize(topic.name),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: JournalSpacing.x2),
                    Eyebrow(entryCountLabel),
                    const SizedBox(width: JournalSpacing.x2),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (topic.aliases.isNotEmpty) ...[
            const SizedBox(height: JournalSpacing.x2),
            Wrap(
              spacing: JournalSpacing.x2,
              runSpacing: JournalSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final alias in topic.aliases)
                  // Removing an alias is an edit, not a glance, so the
                  // control for it only appears once the row is expanded —
                  // a collapsed row shows what the diary knows, not a grid
                  // of remove buttons.
                  if (_expanded)
                    _AliasChip(
                      alias: alias,
                      topicName: topic.name,
                      onRemove: () =>
                          unawaited(notifier.removeAlias(topic.id, alias)),
                    )
                  else
                    StatusBadge(alias),
              ],
            ),
          ],
          if (_expanded) ...[
            const SizedBox(height: JournalSpacing.x3),
            TextField(
              key: ValueKey('topic-draft-${topic.id}'),
              controller: _draft,
              decoration: InputDecoration(
                hintText: 'Another word for ${topic.name}',
                border: const OutlineInputBorder(
                  borderRadius: JournalShapes.small,
                ),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            const SizedBox(height: JournalSpacing.x2),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _draft,
              builder: (context, value, _) => PillButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => unawaited(_submit()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 16),
                    const SizedBox(width: JournalSpacing.x2),
                    Text('Add', style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

/// One taught spelling, with a remove button sized to the platform's minimum
/// touch target regardless of how small its icon is drawn.
class _AliasChip extends StatelessWidget {
  const _AliasChip({
    required this.alias,
    required this.topicName,
    required this.onRemove,
  });

  final String alias;
  final String topicName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusBadge(alias),
      IconButton(
        onPressed: onRemove,
        icon: const Icon(Icons.close, size: 14),
        tooltip: 'Remove the alias $alias from $topicName',
      ),
    ],
  );
}
