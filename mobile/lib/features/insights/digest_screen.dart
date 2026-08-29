import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/diary/digest.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// [R-2] The sheet a tap on the weekly digest notification opens: one
/// pattern, one recommendation, one movement figure.
///
/// Takes an already-fetched [digest] rather than fetching its own -- the
/// fetch happens once, in `app.dart`'s digest-tap handler, specifically so
/// that handler can decide *before* navigating here whether the backend
/// answered at all. Task 2's "if the digest API is unreachable at fire time,
/// the notification simply opens Insights" is a routing decision, not
/// something this screen could render its way out of: a sheet with a
/// perpetual spinner or a stale cached response would violate "never show
/// stale content as fresh" just as badly as an error would, so the decision
/// is made once, upstream, and this screen only ever renders a [Digest] that
/// really did just arrive.
///
/// Every sentence here is the backend's own — [DigestHighlight.sentence],
/// [DigestMovement.sentence] and the recommendation's own `sentence` field
/// (`Recommendation` in `core/diary/pattern.dart`) are rendered verbatim,
/// the same `mobile/CLAUDE.md` rule every other insights screen in this app
/// follows.
class DigestScreen extends StatelessWidget {
  /// Builds the digest sheet for [digest].
  const DigestScreen({super.key, required this.digest});

  /// The week's digest, fetched once before this screen was pushed.
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = digest.highlight;
    final recommendation = digest.recommendation;
    final movement = digest.movement;
    final hasAnyPart = highlight != null || recommendation != null;
    final nothingToShow = digest.empty || (!hasAnyPart && movement == null);

    return Scaffold(
      appBar: AppBar(title: const Text('Your week in patterns')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(JournalSpacing.x4),
          children: [
            if (nothingToShow)
              _EmptyDigestCard(entryCount: digest.entryCount)
            else ...[
              Text(
                '${digest.entryCount} '
                '${digest.entryCount == 1 ? 'entry' : 'entries'} this week',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: JournalSpacing.x4),
              if (highlight != null) ...[
                _DigestPartCard(
                  eyebrow: 'This week’s pattern',
                  body: highlight.sentence,
                  onOpenInsights: () => _openInsights(context),
                ),
                const SizedBox(height: JournalSpacing.x4),
              ],
              if (recommendation != null) ...[
                _DigestPartCard(
                  eyebrow: 'Worth trying',
                  title: recommendation.headline,
                  body: recommendation.sentence,
                  onOpenInsights: () => _openInsights(context),
                ),
                const SizedBox(height: JournalSpacing.x4),
              ],
              if (movement != null)
                _DigestPartCard(eyebrow: 'Movement', body: movement.sentence),
            ],
          ],
        ),
      ),
    );
  }

  void _openInsights(BuildContext context) =>
      context.go(AppConfig.insightsPath);
}

/// One of the digest's three parts: an eyebrow label, an optional title, a
/// body sentence, and — where a pattern backs the part — a link into
/// Insights.
class _DigestPartCard extends StatelessWidget {
  const _DigestPartCard({
    required this.eyebrow,
    required this.body,
    this.title,
    this.onOpenInsights,
  });

  final String eyebrow;
  final String? title;
  final String body;
  final VoidCallback? onOpenInsights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: JournalSpacing.x2),
          ],
          Text(body, style: theme.textTheme.bodyMedium),
          if (onOpenInsights != null) ...[
            const SizedBox(height: JournalSpacing.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onOpenInsights,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('See in Insights'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the sheet shows when the week had nothing to report: an empty diary
/// week, or entries that never added up to a pattern, a recommendation, or a
/// movement figure.
class _EmptyDigestCard extends StatelessWidget {
  const _EmptyDigestCard({required this.entryCount});

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = entryCount == 0
        ? "You didn't write anything this week."
        : '$entryCount ${entryCount == 1 ? 'entry' : 'entries'} this week, '
              'but nothing new to report yet.';
    return JournalCard(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
