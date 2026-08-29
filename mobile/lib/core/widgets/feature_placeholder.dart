import 'package:flutter/material.dart';

/// The "this screen is yours to build" body every new app starts with.
class PlaceholderView extends StatelessWidget {
  /// Creates a placeholder describing what belongs on this screen.
  const PlaceholderView({
    super.key,
    this.icon,
    required this.title,
    required this.message,
  });

  /// An icon shown above [title], or `null` for none.
  final IconData? icon;

  /// The name of the screen this placeholder stands in for.
  final String title;

  /// A sentence saying which file to replace.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
