import 'package:flutter/material.dart';

import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';

/// Where every `PremiumLock`'s Upgrade action leads (M-3, #48).
///
/// A placeholder, deliberately: the issue's own out-of-scope line reserves
/// the Play Billing purchase flow and the lifetime SKU for a later,
/// store-launch ticket. What this ticket owns is the wiring -- every locked
/// state genuinely opens a real screen rather than a dead tap target -- not
/// a working purchase. Nothing here calls a payments API or writes an
/// entitlement; the manual tier-flip demo (`POST /billing/admin/grant`)
/// stays the only way to change tier until that ticket lands.
class UpgradeScreen extends StatelessWidget {
  /// Creates the upgrade screen.
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(JournalSpacing.x5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Premium', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: JournalSpacing.x3),
                  Text(
                    'Patterns and trajectories across your full history, '
                    'N-of-1 experiments, and the weekly digest.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: JournalSpacing.x5),
                  JournalCard(
                    child: Text(
                      'Purchasing is not available in this build yet -- '
                      'this screen is a placeholder the store-launch ticket '
                      'wires up to Play Billing.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
