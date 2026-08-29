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
      for (final topic in topics) ...[
        // Keyed on the topic's id, not its position: without this, removing
        // or reordering a topic would hand this element's leftover draft
        // controller to whatever topic now lands at the same index.
        _TopicCard(key: ValueKey(topic.id), topic: topic),
        const SizedBox(height: JournalSpacing.x3),
      ],
    ];
  }
}

/// One topic: its name, entry count, existing aliases, and the field for
/// teaching it a new one.
///
/// A [ConsumerStatefulWidget] rather than a stateless one because the draft
/// alias is per-card, ephemeral input that has no business living in
/// [TopicsController]. Its caller keys each card on [TopicDetail.id], so
/// removing or reordering a topic never hands this card's draft controller
/// to a different topic that happens to land at the same list position.
class _TopicCard extends ConsumerStatefulWidget {
  const _TopicCard({super.key, required this.topic});

  final TopicDetail topic;

  @override
  ConsumerState<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends ConsumerState<_TopicCard> {
  final TextEditingController _draft = TextEditingController();

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

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _capitalize(topic.name),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Eyebrow(
                '${topic.entryCount} ${topic.entryCount == 1 ? 'entry' : 'entries'}',
              ),
            ],
          ),
          if (topic.aliases.isNotEmpty) ...[
            const SizedBox(height: JournalSpacing.x3),
            Wrap(
              spacing: JournalSpacing.x2,
              runSpacing: JournalSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final alias in topic.aliases)
                  _AliasChip(
                    alias: alias,
                    topicName: topic.name,
                    onRemove: () =>
                        unawaited(notifier.removeAlias(topic.id, alias)),
                  ),
              ],
            ),
          ],
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
