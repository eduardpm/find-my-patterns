import '../screen_registry.dart';

/// `lib/features/experiments/`.
final experiments = ScreenArea(
  name: 'experiments',
  cases: [],
  unswept: const {
    'features/experiments/active_experiment_banner.dart',
    'features/experiments/comparison_bars.dart',
    'features/experiments/experiment_results_screen.dart',
    'features/experiments/experiment_setup_sheet.dart',
  },
);
