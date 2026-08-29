import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HypothesisKind', () {
    test("'less_of' maps to lessOf, else moreOf", () {
      expect(HypothesisKind.fromWire('less_of'), HypothesisKind.lessOf);
      expect(HypothesisKind.fromWire('more_of'), HypothesisKind.moreOf);
      expect(HypothesisKind.fromWire('anything'), HypothesisKind.moreOf);
    });

    test('wireValue round-trips fromWire', () {
      expect(HypothesisKind.moreOf.wireValue, 'more_of');
      expect(HypothesisKind.lessOf.wireValue, 'less_of');
    });
  });

  group('ExperimentStatus', () {
    test("'finished' and 'abandoned' map to their namesakes, else active", () {
      expect(ExperimentStatus.fromWire('finished'), ExperimentStatus.finished);
      expect(
        ExperimentStatus.fromWire('abandoned'),
        ExperimentStatus.abandoned,
      );
      expect(ExperimentStatus.fromWire('active'), ExperimentStatus.active);
      expect(ExperimentStatus.fromWire('anything'), ExperimentStatus.active);
    });
  });

  Experiment buildExperiment({
    CalendarDate? startDate,
    CalendarDate? endDate,
    String patternTopic = 'exercise',
    String patternFeeling = 'exhausted',
  }) => Experiment(
    'experiment-1',
    patternTopic,
    patternFeeling,
    HypothesisKind.moreOf,
    startDate ?? const CalendarDate(2026, 8, 1),
    endDate ?? const CalendarDate(2026, 8, 7),
    ExperimentStatus.active,
    DateTime.utc(2026, 8, 1),
    ExperimentConstants.placeholder,
  );

  group('Experiment.lengthDays', () {
    test('is inclusive of both ends', () {
      final experiment = buildExperiment(
        startDate: const CalendarDate(2026, 8, 1),
        endDate: const CalendarDate(2026, 8, 7),
      );
      expect(experiment.lengthDays, 7);
    });
  });

  group('Experiment.dayNumber', () {
    final experiment = buildExperiment(
      startDate: const CalendarDate(2026, 8, 1),
      endDate: const CalendarDate(2026, 8, 7),
    );

    test('reads 1 on the start date', () {
      expect(experiment.dayNumber(const CalendarDate(2026, 8, 1)), 1);
    });

    test('reads day 3 on the third day', () {
      expect(experiment.dayNumber(const CalendarDate(2026, 8, 3)), 3);
    });

    test('clamps to 1 before the experiment has started', () {
      expect(experiment.dayNumber(const CalendarDate(2026, 7, 30)), 1);
    });

    test('clamps to the last day once the window has passed', () {
      expect(experiment.dayNumber(const CalendarDate(2026, 8, 20)), 7);
    });
  });

  group('Experiment.matches', () {
    test('is true for the same topic and feeling', () {
      final experiment = buildExperiment(
        patternTopic: 'exercise',
        patternFeeling: 'exhausted',
      );
      expect(
        experiment.matches(topic: 'exercise', feeling: 'exhausted'),
        isTrue,
      );
    });

    test('is false for a different topic or feeling', () {
      final experiment = buildExperiment(
        patternTopic: 'exercise',
        patternFeeling: 'exhausted',
      );
      expect(
        experiment.matches(topic: 'coffee', feeling: 'exhausted'),
        isFalse,
      );
      expect(experiment.matches(topic: 'exercise', feeling: 'happy'), isFalse);
      expect(experiment.matches(topic: 'exercise', feeling: null), isFalse);
    });
  });

  group('experimentConstantsFromJson', () {
    test('decodes every field', () {
      final constants = experimentConstantsFromJson({
        'default_length_days': 10,
        'min_length_days': 7,
        'max_length_days': 28,
        'min_bucket_entries': 3,
      });
      expect(constants.defaultLengthDays, 10);
      expect(constants.minLengthDays, 7);
      expect(constants.maxLengthDays, 28);
      expect(constants.minBucketEntries, 3);
    });

    test('defaults every field to the placeholder for a missing key', () {
      final constants = experimentConstantsFromJson(const {});
      expect(constants.defaultLengthDays, 7);
      expect(constants.minLengthDays, 7);
      expect(constants.maxLengthDays, 28);
      expect(constants.minBucketEntries, 3);
    });
  });

  Map<String, Object?> experimentJson({
    String id = 'experiment-1',
    String patternTopic = 'exercise',
    String patternFeeling = 'exhausted',
    String hypothesisKind = 'more_of',
    String startDate = '2026-08-01',
    String endDate = '2026-08-07',
    String status = 'active',
  }) => {
    'id': id,
    'pattern_topic': patternTopic,
    'pattern_feeling': patternFeeling,
    'hypothesis_kind': hypothesisKind,
    'start_date': startDate,
    'end_date': endDate,
    'status': status,
    'created_at': '2026-08-01T09:00:00Z',
    'constants': {
      'default_length_days': 7,
      'min_length_days': 7,
      'max_length_days': 28,
      'min_bucket_entries': 3,
    },
  };

  group('experimentFromJson', () {
    test('decodes a full experiment', () {
      final experiment = experimentFromJson(experimentJson());
      expect(experiment.id, 'experiment-1');
      expect(experiment.patternTopic, 'exercise');
      expect(experiment.patternFeeling, 'exhausted');
      expect(experiment.hypothesisKind, HypothesisKind.moreOf);
      expect(experiment.startDate, const CalendarDate(2026, 8, 1));
      expect(experiment.endDate, const CalendarDate(2026, 8, 7));
      expect(experiment.status, ExperimentStatus.active);
      expect(experiment.constants.maxLengthDays, 28);
    });

    test('defaults status to active and hypothesis to moreOf when missing', () {
      final json = experimentJson()
        ..remove('status')
        ..remove('hypothesis_kind');
      final experiment = experimentFromJson(json);
      expect(experiment.status, ExperimentStatus.active);
      expect(experiment.hypothesisKind, HypothesisKind.moreOf);
    });
  });

  group('experimentWindowFromJson', () {
    test('decodes a full window', () {
      final window = experimentWindowFromJson({
        'start_date': '2026-08-01',
        'end_date': '2026-08-07',
        'total_days': 7,
        'days_with_topic': 4,
        'present_count': 1,
        'present_total': 4,
        'absent_count': 1,
        'absent_total': 2,
        'present_rate': 0.25,
        'absent_rate': 0.5,
      });
      expect(window.startDate, const CalendarDate(2026, 8, 1));
      expect(window.endDate, const CalendarDate(2026, 8, 7));
      expect(window.totalDays, 7);
      expect(window.daysWithTopic, 4);
      expect(window.presentCount, 1);
      expect(window.presentTotal, 4);
      expect(window.absentCount, 1);
      expect(window.absentTotal, 2);
      expect(window.presentRate, closeTo(0.25, 1e-9));
      expect(window.absentRate, closeTo(0.5, 1e-9));
    });

    test('a null rate decodes to null, never zero', () {
      final window = experimentWindowFromJson({
        'start_date': '2026-08-01',
        'end_date': '2026-08-07',
        'present_rate': null,
        'absent_rate': null,
      });
      expect(window.presentRate, isNull);
      expect(window.absentRate, isNull);
    });
  });

  group('experimentResultsFromJson', () {
    test('decodes the whole results payload', () {
      final results = experimentResultsFromJson({
        'experiment': experimentJson(),
        'experiment_window': {
          'start_date': '2026-08-01',
          'end_date': '2026-08-07',
          'total_days': 7,
          'days_with_topic': 4,
          'present_count': 1,
          'present_total': 4,
          'absent_count': 1,
          'absent_total': 2,
          'present_rate': 0.25,
          'absent_rate': 0.5,
        },
        'baseline_window': {
          'start_date': '2026-07-25',
          'end_date': '2026-07-31',
          'total_days': 7,
          'days_with_topic': 5,
          'present_count': 3,
          'present_total': 5,
          'absent_count': 1,
          'absent_total': 2,
          'present_rate': 0.6,
          'absent_rate': 0.5,
        },
        'verdict_text':
            'During the experiment you mentioned exercise on 4 '
            'of 7 days.',
        'insufficient_data': false,
        'constants': {
          'default_length_days': 7,
          'min_length_days': 7,
          'max_length_days': 28,
          'min_bucket_entries': 3,
        },
      });

      expect(results.experiment.id, 'experiment-1');
      expect(results.experimentWindow.presentTotal, 4);
      expect(results.baselineWindow.presentTotal, 5);
      expect(
        results.verdictText,
        'During the experiment you mentioned exercise on 4 of 7 days.',
      );
      expect(results.insufficientData, isFalse);
      expect(results.constants.minBucketEntries, 3);
    });
  });
}
