import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatternDirection', () {
    test("'change' and 'none' map to their namesakes, else keep", () {
      expect(PatternDirection.fromWire('change'), PatternDirection.change);
      expect(PatternDirection.fromWire('none'), PatternDirection.none);
      expect(PatternDirection.fromWire('keep'), PatternDirection.keep);
      expect(PatternDirection.fromWire('anything'), PatternDirection.keep);
    });
  });

  group('PatternKind', () {
    test("'inverse' maps to inverse, else forward", () {
      expect(PatternKind.fromWire('inverse'), PatternKind.inverse);
      expect(PatternKind.fromWire('forward'), PatternKind.forward);
      expect(PatternKind.fromWire('anything'), PatternKind.forward);
    });
  });

  group('PatternStatus', () {
    test("'historical' maps to historical, else active", () {
      expect(PatternStatus.fromWire('historical'), PatternStatus.historical);
      expect(PatternStatus.fromWire('active'), PatternStatus.active);
      expect(PatternStatus.fromWire('anything'), PatternStatus.active);
    });
  });

  group('WithdrawalReason', () {
    test('resolves every known reason', () {
      expect(
        WithdrawalReason.fromWire('below_lift'),
        WithdrawalReason.belowLift,
      );
      expect(
        WithdrawalReason.fromWire('no_longer_confirmed'),
        WithdrawalReason.noLongerConfirmed,
      );
      expect(
        WithdrawalReason.fromWire('topic_merged'),
        WithdrawalReason.topicMerged,
      );
      expect(
        WithdrawalReason.fromWire('below_threshold'),
        WithdrawalReason.belowThreshold,
      );
    });

    test('anything unrecognised falls back to belowThreshold', () {
      expect(
        WithdrawalReason.fromWire('never_heard_of_this'),
        WithdrawalReason.belowThreshold,
      );
    });
  });

  group('EngineConstants.placeholder', () {
    test('carries the documented placeholder values', () {
      const c = EngineConstants.placeholder;
      expect(c.minOccurrenceThreshold, 3);
      expect(c.recencyWindowDays, 30);
      expect(c.minLift, 1.5);
      expect(c.strongLift, 3.0);
      expect(c.strongMinOccurrences, 5);
      expect(c.minComparisonEntries, 3);
      expect(c.collinearityThreshold, 0.8);
      expect(c.minBucketEntries, 3);
      expect(c.minIntensity, 1);
      expect(c.maxIntensity, 5);
    });
  });

  final catalog = FeelingCatalog([
    const Feeling('anxious', 'Anxious', Valence.negative, 'tense'),
  ]);

  group('patternEvidenceFromJson', () {
    test('decodes every field', () {
      final evidence = patternEvidenceFromJson({
        'entry_id': 'e1',
        'entry_date': '2026-08-20',
        'raw_text': 'Back to back meetings.',
        'feeling_keys': ['anxious'],
        'feeling_source': 'confirmed',
      }, catalog);
      expect(evidence.entryId, 'e1');
      expect(evidence.entryDate, const CalendarDate(2026, 8, 20));
      expect(evidence.rawText, 'Back to back meetings.');
      expect(evidence.feelings.single.label, 'Anxious');
      expect(evidence.feelingSource, FeelingSource.confirmed);
    });

    test('feeling_keys defaults to empty', () {
      final evidence = patternEvidenceFromJson({
        'entry_id': 'e1',
        'entry_date': '2026-08-20',
        'raw_text': 'x',
      }, catalog);
      expect(evidence.feelings, isEmpty);
    });

    test('feeling_source defaults to confirmed', () {
      final evidence = patternEvidenceFromJson({
        'entry_id': 'e1',
        'entry_date': '2026-08-20',
        'raw_text': 'x',
      }, catalog);
      expect(evidence.feelingSource, FeelingSource.confirmed);
    });
  });

  group('confounderFromJson', () {
    test('decodes every field', () {
      final confounder = confounderFromJson({
        'topic': 'coffee',
        'co_occurrence_rate': 0.9,
        'both_count': 9,
        'only_this_count': 1,
        'only_other_count': 2,
        'neither_count': 8,
        'inseparable': false,
        'note': 'meetings and coffee appear together',
      });
      expect(confounder.topic, 'coffee');
      expect(confounder.coOccurrenceRate, 0.9);
      expect(confounder.bothCount, 9);
      expect(confounder.onlyThisCount, 1);
      expect(confounder.onlyOtherCount, 2);
      expect(confounder.neitherCount, 8);
      expect(confounder.inseparable, isFalse);
      expect(confounder.note, 'meetings and coffee appear together');
    });

    test('every numeric/bool/string field defaults to its inert value', () {
      final confounder = confounderFromJson({'topic': 'coffee'});
      expect(confounder.coOccurrenceRate, 0.0);
      expect(confounder.bothCount, 0);
      expect(confounder.onlyThisCount, 0);
      expect(confounder.onlyOtherCount, 0);
      expect(confounder.neitherCount, 0);
      expect(confounder.inseparable, isFalse);
      expect(confounder.note, '');
    });
  });

  Map<String, Object?> fullPatternJson({
    Map<String, Object?> overrides = const {},
  }) => {
    'id': 'p1',
    'topic': 'meetings',
    'feeling': 'anxious',
    'occurrence_count': 8,
    'direction': 'change',
    'narrative_text': 'You felt anxious in 8 of 12 entries…',
    'suggestion_text': 'Pay attention to meetings.',
    'last_updated_at': '2026-08-26T09:00:00.000000',
    'kind': 'forward',
    'lifetime_count': 20,
    'status': 'active',
    'present_count': 8,
    'present_total': 12,
    'absent_count': 3,
    'absent_total': 28,
    'present_rate': 0.6666666666666666,
    'absent_rate': 0.10714285714285714,
    'base_rate': 0.275,
    'lift': 6.222222222222222,
    'is_strong': true,
    'last_occurrence_date': '2026-08-25',
    'days_since_last_occurrence': 1,
    'confounders': [
      {
        'topic': 'coffee',
        'co_occurrence_rate': 0.9,
        'both_count': 9,
        'only_this_count': 1,
        'only_other_count': 2,
        'neither_count': 8,
        'inseparable': false,
        'note': 'meetings and coffee appear together in 9 of 10 entries…',
      },
    ],
    'evidence': [
      {
        'entry_id': 'e1',
        'entry_date': '2026-08-20',
        'raw_text': 'Back to back meetings.',
        'feeling_keys': ['anxious'],
        'feeling_source': 'confirmed',
      },
    ],
    ...overrides,
  };

  group('patternFromJson', () {
    test('carries every figure through untouched', () {
      final pattern = patternFromJson(fullPatternJson(), catalog);
      expect(pattern.kind, PatternKind.forward);
      expect(pattern.status, PatternStatus.active);
      expect(pattern.direction, PatternDirection.change);
      expect(pattern.occurrenceCount, 8);
      expect(pattern.lifetimeCount, 20);
      expect(pattern.presentRate, 0.6666666666666666);
      expect(pattern.lift, 6.222222222222222);
      expect(pattern.isStrong, isTrue);
      expect(pattern.confounders.single.topic, 'coffee');
      expect(pattern.evidence, hasLength(1));
      expect(pattern.evidence.single.entryId, 'e1');
      expect(pattern.evidence.single.feelings.single.label, 'Anxious');
      expect(pattern.lastUpdatedAt, DateTime.utc(2026, 8, 26, 9, 0, 0));
      expect(pattern.lastOccurrenceDate, const CalendarDate(2026, 8, 25));
      expect(pattern.daysSinceLastOccurrence, 1);
    });

    test('an absent lift stays null rather than becoming zero', () {
      final pattern = patternFromJson(
        fullPatternJson(
          overrides: {
            'lift': null,
            'comparison_reason': 'insufficient_comparison',
            'comparison_note':
                'Not enough entries without meetings to compare.',
            'is_strong': false,
          },
        ),
        catalog,
      );
      expect(pattern.lift, isNull);
      expect(pattern.comparisonReason, 'insufficient_comparison');
      expect(pattern.comparisonNote, isNotEmpty);
    });

    test(
      'a response from a pre-roadmap backend still parses with inert defaults',
      () {
        final pattern = patternFromJson({
          'id': 'p-old',
          'topic': 'tea',
          'feeling': 'anxious',
          'occurrence_count': 3,
          'direction': 'keep',
          'narrative_text': '…',
          'suggestion_text': '…',
          'last_updated_at': '2026-08-26T09:00:00.000000',
        }, catalog);

        expect(pattern.kind, PatternKind.forward);
        expect(pattern.status, PatternStatus.active);
        expect(pattern.lift, isNull);
        expect(pattern.confounders, isEmpty);
        expect(pattern.evidence, isEmpty);
        expect(pattern.lifetimeCount, 0);
        expect(pattern.presentCount, 0);
        expect(pattern.presentTotal, 0);
        expect(pattern.absentCount, 0);
        expect(pattern.absentTotal, 0);
        expect(pattern.presentRate, isNull);
        expect(pattern.absentRate, isNull);
        expect(pattern.baseRate, 0.0);
        expect(pattern.isStrong, isFalse);
        expect(pattern.lastOccurrenceDate, isNull);
        expect(pattern.daysSinceLastOccurrence, isNull);
        expect(pattern.historicalNote, isNull);
        expect(pattern.comparisonReason, isNull);
        expect(pattern.comparisonNote, isNull);
      },
    );

    // P0-2: `patternFromJson` used to compare `json['direction']` to
    // `'change'` directly, bypassing `PatternDirection.fromWire` entirely,
    // so a `'none'` value from the backend silently became `keep` instead
    // of `none`. Routing through `fromWire` fixed that.
    test("a 'none' direction decodes to PatternDirection.none, not keep", () {
      final pattern = patternFromJson(
        fullPatternJson(overrides: {'direction': 'none'}),
        catalog,
      );
      expect(pattern.direction, PatternDirection.none);
    });

    test('feeling resolves through the catalog and drops when unknown', () {
      final pattern = patternFromJson(fullPatternJson(), catalog);
      expect(pattern.feeling?.key, 'anxious');

      final unknown = patternFromJson(
        fullPatternJson(overrides: {'feeling': 'invented'}),
        catalog,
      );
      expect(unknown.feeling, isNull);
    });

    test('lift accepts an integer JSON value, not only a double', () {
      final pattern = patternFromJson(
        fullPatternJson(overrides: {'lift': 2}),
        catalog,
      );
      expect(pattern.lift, 2.0);
    });

    test('base_rate accepts an integer JSON value', () {
      final pattern = patternFromJson(
        fullPatternJson(overrides: {'base_rate': 1}),
        catalog,
      );
      expect(pattern.baseRate, 1.0);
    });

    test('an unparseable last_updated_at falls back to epoch UTC', () {
      final pattern = patternFromJson(
        fullPatternJson(overrides: {'last_updated_at': 'nonsense'}),
        catalog,
      );
      expect(pattern.lastUpdatedAt, DateTime.utc(1970));
    });

    test('an unparseable last_occurrence_date falls back to null', () {
      final pattern = patternFromJson(
        fullPatternJson(overrides: {'last_occurrence_date': 'nonsense'}),
        catalog,
      );
      expect(pattern.lastOccurrenceDate, isNull);
    });

    test('historical_note is carried when present', () {
      final pattern = patternFromJson(
        fullPatternJson(
          overrides: {'historical_note': 'Held often enough once.'},
        ),
        catalog,
      );
      expect(pattern.historicalNote, 'Held often enough once.');
    });

    // R-1: `recommendation` is `null` for almost every pattern -- absent
    // entirely is what a pattern the engine did not promote, and a backend
    // that predates this field, both decode to.
    test('recommendation defaults to null when the field is absent', () {
      final pattern = patternFromJson(fullPatternJson(), catalog);
      expect(pattern.recommendation, isNull);
    });

    test('decodes a "Worth trying" recommendation when the pattern carries '
        'one (R-1)', () {
      final pattern = patternFromJson(
        fullPatternJson(
          overrides: {
            'recommendation': {
              'action_topic': 'exercise',
              'headline': 'More exercise days',
              'sentence':
                  'On days without exercise, anxious is 2.7× more likely '
                  '(4 of 6 without vs 1 of 4 with). More exercise days may '
                  "help — here's the evidence.",
              'pattern_ref': 'p1',
            },
          },
        ),
        catalog,
      );
      final recommendation = pattern.recommendation!;
      expect(recommendation.actionTopic, 'exercise');
      expect(recommendation.headline, 'More exercise days');
      expect(
        recommendation.sentence,
        contains('4 of 6 without vs 1 of 4 with'),
      );
      // The tap-through key: the pattern this recommendation points back at.
      expect(recommendation.patternRef, 'p1');
    });

    test(
      'a non-object recommendation value decodes to null rather than throwing',
      () {
        final pattern = patternFromJson(
          fullPatternJson(overrides: {'recommendation': 'not an object'}),
          catalog,
        );
        expect(pattern.recommendation, isNull);
      },
    );
  });

  group('withdrawalFromJson', () {
    test('withdrawals carry their counts and reason', () {
      final withdrawal = withdrawalFromJson({
        'id': 'w1',
        'topic': 'tea',
        'feeling': 'calm',
        'previous_count': 3,
        'new_count': 2,
        'reason': 'below_threshold',
        'detail_text': 'tea → calm was withdrawn…',
        'withdrawn_at': '2026-08-26T09:00:00.000000',
        'is_new': true,
      });
      expect(withdrawal.reason, WithdrawalReason.belowThreshold);
      expect(withdrawal.previousCount, 3);
      expect(withdrawal.newCount, 2);
      expect(withdrawal.isNew, isTrue);
      expect(withdrawal.withdrawnAt, DateTime.utc(2026, 8, 26, 9, 0, 0));
    });

    test(
      'a weakened association reason is distinct from thinned-out evidence',
      () {
        final withdrawal = withdrawalFromJson({
          'id': 'w2',
          'topic': 'reading',
          'feeling': 'anxious',
          'kind': 'inverse',
          'previous_count': 12,
          'new_count': 12,
          'reason': 'below_lift',
          'detail_text': '…still 12 occurrences, but the association…',
          'withdrawn_at': '2026-08-26T09:00:00.000000',
        });
        expect(withdrawal.reason, WithdrawalReason.belowLift);
        expect(withdrawal.kind, PatternKind.inverse);
        expect(withdrawal.previousCount, withdrawal.newCount);
      },
    );

    test('an unrecognised reason falls back rather than crashing', () {
      final withdrawal = withdrawalFromJson({
        'id': 'w3',
        'topic': 'tea',
        'feeling': 'calm',
        'reason': 'something_this_build_has_never_heard_of',
        'withdrawn_at': '2026-08-26T09:00:00.000000',
      });
      expect(withdrawal.reason, WithdrawalReason.belowThreshold);
    });

    test('defaults for a minimal payload', () {
      final withdrawal = withdrawalFromJson({
        'id': 'w4',
        'topic': 'tea',
        'feeling': 'calm',
        'withdrawn_at': '2026-08-26T09:00:00.000000',
      });
      expect(withdrawal.kind, PatternKind.forward);
      expect(withdrawal.previousCount, 0);
      expect(withdrawal.newCount, 0);
      expect(withdrawal.detailText, '');
      expect(withdrawal.isNew, isFalse);
    });

    test('an unparseable withdrawn_at falls back to epoch UTC', () {
      final withdrawal = withdrawalFromJson({
        'id': 'w5',
        'topic': 'tea',
        'feeling': 'calm',
        'withdrawn_at': 'nonsense',
      });
      expect(withdrawal.withdrawnAt, DateTime.utc(1970));
    });
  });

  group('engineConstantsFromJson', () {
    test('the engine constants are read rather than assumed', () {
      final constants = engineConstantsFromJson({
        'recency_window_days': 14,
        'min_occurrence_threshold': 5,
      });
      expect(constants.recencyWindowDays, 14);
      expect(constants.minOccurrenceThreshold, 5);
    });

    test('defaults match the placeholder for a bare payload', () {
      final constants = engineConstantsFromJson({});
      expect(constants.minOccurrenceThreshold, 3);
      expect(constants.recencyWindowDays, 30);
      expect(constants.minLift, 1.5);
      expect(constants.strongLift, 3.0);
      expect(constants.strongMinOccurrences, 5);
      expect(constants.minComparisonEntries, 3);
      expect(constants.collinearityThreshold, 0.8);
      expect(constants.minBucketEntries, 3);
      expect(constants.minIntensity, 1);
      expect(constants.maxIntensity, 5);
    });
  });

  group('insightsResultFromJson', () {
    test('decodes patterns, withdrawals and the insufficient-data flag', () {
      final result = insightsResultFromJson({
        'patterns': [fullPatternJson()],
        'withdrawals': [
          {
            'id': 'w1',
            'topic': 'tea',
            'feeling': 'calm',
            'withdrawn_at': '2026-08-26T09:00:00.000000',
          },
        ],
        'new_withdrawal_count': 1,
        'insufficient_data': false,
        'constants': <String, Object?>{},
      }, catalog);
      expect(result.patterns, hasLength(1));
      expect(result.withdrawals.single.id, 'w1');
      expect(result.newWithdrawalCount, 1);
      expect(result.insufficientData, isFalse);
      expect(result.constants.recencyWindowDays, 30);
    });

    test('every list defaults to empty', () {
      final result = insightsResultFromJson({}, catalog);
      expect(result.patterns, isEmpty);
      expect(result.withdrawals, isEmpty);
      expect(result.newWithdrawalCount, 0);
      expect(result.insufficientData, isFalse);
    });
  });

  group('whenBucketFromJson', () {
    test('decodes every field', () {
      final bucket = whenBucketFromJson({
        'key': 'monday',
        'label': 'Monday',
        'entry_count': 5,
        'average_valence': 0.2,
        'negative_rate': 0.4,
        'sufficient': true,
      });
      expect(bucket.key, 'monday');
      expect(bucket.entryCount, 5);
      expect(bucket.averageValence, 0.2);
      expect(bucket.negativeRate, 0.4);
      expect(bucket.sufficient, isTrue);
    });

    test('defaults for a minimal payload', () {
      final bucket = whenBucketFromJson({'key': 'monday', 'label': 'Monday'});
      expect(bucket.entryCount, 0);
      expect(bucket.averageValence, isNull);
      expect(bucket.negativeRate, isNull);
      expect(bucket.sufficient, isFalse);
    });
  });

  group('whenInsightsFromJson', () {
    test('decodes every field', () {
      final when = whenInsightsFromJson({
        'window_days': 30,
        'min_bucket_entries': 3,
        'total_entries': 40,
        'weekdays': [
          {'key': 'monday', 'label': 'Monday'},
        ],
        'times_of_day': [
          {'key': 'morning', 'label': 'Morning'},
        ],
        'best_weekday': 'friday',
        'worst_weekday': 'monday',
        'best_time_of_day': 'morning',
        'worst_time_of_day': 'evening',
        'hourly': [
          {
            'key': '18',
            'label': '18:00–20:00',
            'entry_count': 7,
            'average_valence': -0.27,
            'negative_rate': 0.5,
            'sufficient': true,
          },
        ],
        'best_hour': '08',
        'worst_hour': '22',
        'busiest_time_of_day': 'evening',
      });
      expect(when.windowDays, 30);
      expect(when.totalEntries, 40);
      expect(when.weekdays.single.key, 'monday');
      expect(when.timesOfDay.single.key, 'morning');
      expect(when.bestWeekday, 'friday');
      expect(when.worstTimeOfDay, 'evening');
      expect(when.hourly.single.key, '18');
      expect(when.hourly.single.label, '18:00–20:00');
      expect(when.hourly.single.averageValence, -0.27);
      expect(when.bestHour, '08');
      expect(when.worstHour, '22');
      expect(when.busiestTimeOfDay, 'evening');
    });

    test('defaults for a bare payload — CH-5 fields included', () {
      final when = whenInsightsFromJson({});
      expect(when.windowDays, 30);
      expect(when.minBucketEntries, 3);
      expect(when.totalEntries, 0);
      expect(when.weekdays, isEmpty);
      expect(when.timesOfDay, isEmpty);
      expect(when.bestWeekday, isNull);
      expect(when.worstWeekday, isNull);
      expect(when.bestTimeOfDay, isNull);
      expect(when.worstTimeOfDay, isNull);
      // A backend that predates CH-5 sends no `hourly` at all — this
      // decodes to an empty list, not an error, same as `weekdays` and
      // `times_of_day` already do above.
      expect(when.hourly, isEmpty);
      expect(when.bestHour, isNull);
      expect(when.worstHour, isNull);
      expect(when.busiestTimeOfDay, isNull);
    });
  });

  group('patternEchoFromJson', () {
    test('decodes every field', () {
      final echo = patternEchoFromJson({
        'pattern_id': 'p1',
        'topic': 'meetings',
        'feeling': 'anxious',
        'occurrence_count': 8,
        'present_count': 8,
        'present_total': 12,
        'lift': 6.2,
        'narrative_text': 'You felt anxious in 8 of 12 entries…',
      });
      expect(echo.patternId, 'p1');
      expect(echo.topic, 'meetings');
      expect(echo.feeling, 'anxious');
      expect(echo.occurrenceCount, 8);
      expect(echo.presentCount, 8);
      expect(echo.presentTotal, 12);
      expect(echo.lift, 6.2);
      expect(echo.narrativeText, isNotEmpty);
    });

    test('defaults for a minimal payload', () {
      final echo = patternEchoFromJson({
        'pattern_id': 'p1',
        'topic': 'meetings',
        'feeling': 'anxious',
      });
      expect(echo.occurrenceCount, 0);
      expect(echo.presentCount, 0);
      expect(echo.presentTotal, 0);
      expect(echo.lift, isNull);
      expect(echo.narrativeText, '');
    });
  });
}
