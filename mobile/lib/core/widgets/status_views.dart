/// The states a feature screen cycles through, drawn the same way everywhere.
///
/// @docImport '../network/api_error.dart';
/// @docImport 'feature_placeholder.dart';
library;

import 'package:flutter/material.dart';

/// A centred progress indicator, with an optional [label] beneath it.
///
/// The "still working" state. See [PlaceholderView] for the empty state and
/// [ErrorView] for the failed one.
class LoadingView extends StatelessWidget {
  /// Creates a loading indicator.
  const LoadingView({super.key, this.label});

  /// What the app is waiting for, or `null` to show only the indicator.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// A centred failure message, with optional recovery actions.
///
/// [onRetry] adds a Retry button. [onConfigure] adds a button that takes the
/// user to Settings, which is what a [BackendNotConfigured] failure needs —
/// telling someone the server is unset is useless without a way to set it.
class ErrorView extends StatelessWidget {
  /// Creates a failure message.
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.onConfigure,
  });

  /// What went wrong, phrased for the user.
  final String message;

  /// Called when the user asks to try again, or `null` to hide the button.
  final VoidCallback? onRetry;

  /// Called when the user asks to open Settings, or `null` to hide the button.
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null || onConfigure != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null)
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  if (onConfigure != null)
                    FilledButton(
                      onPressed: onConfigure,
                      child: const Text('Open Settings'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
