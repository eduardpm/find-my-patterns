import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntryMode', () {
    test('fromWire: guided maps to guided, anything else is freeform', () {
      expect(EntryMode.fromWire('guided'), EntryMode.guided);
      expect(EntryMode.fromWire('freeform'), EntryMode.freeform);
      expect(EntryMode.fromWire('anything'), EntryMode.freeform);
    });
  });

  group('FeelingSource', () {
    test('fromWire resolves every known source', () {
      expect(FeelingSource.fromWire('suggested'), FeelingSource.suggested);
      expect(FeelingSource.fromWire('confirmed'), FeelingSource.confirmed);
      expect(FeelingSource.fromWire('overridden'), FeelingSource.overridden);
    });

    test('fromWire falls back to unset', () {
      expect(FeelingSource.fromWire('anything_else'), FeelingSource.unset);
      expect(FeelingSource.fromWire(null), FeelingSource.unset);
    });

    test('isConfirmed is true only for confirmed and overridden', () {
      expect(FeelingSource.confirmed.isConfirmed, isTrue);
      expect(FeelingSource.overridden.isConfirmed, isTrue);
      expect(FeelingSource.suggested.isConfirmed, isFalse);
      expect(FeelingSource.unset.isConfirmed, isFalse);
    });
  });

  group('GuidedAnswer', () {
    test('holds its fields', () {
      const answer = GuidedAnswer('q1', 'How was your day?', 'Good.');
      expect(answer.questionKey, 'q1');
      expect(answer.questionText, 'How was your day?');
      expect(answer.answerText, 'Good.');
    });
  });

  group('SuggestedFeeling', () {
    test('holds a feeling and its confidence', () {
      const feeling = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      const suggestion = SuggestedFeeling(feeling, 0.8);
      expect(suggestion.feeling, feeling);
      expect(suggestion.confidence, 0.8);
    });
  });

  group('entryFromJson', () {
    const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
    const sad = Feeling('sad', 'Sad', Valence.negative, 'low');
    final catalog = FeelingCatalog([happy, sad]);

    Map<String, Object?> baseJson({
      Map<String, Object?> overrides = const {},
    }) => {
      'id': 'entry-1',
      'created_at': '2026-07-28T13:05:00Z',
      'entry_date': '2026-07-28',
      'mode': 'freeform',
      'raw_text': 'a day',
      'feeling_source': 'confirmed',
      'version': 4,
      ...overrides,
    };

    test('decodes the required fields', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.id, 'entry-1');
      expect(entry.createdAt, DateTime.utc(2026, 7, 28, 13, 5));
      expect(entry.createdAt.isUtc, isTrue);
      expect(entry.entryDate, const CalendarDate(2026, 7, 28));
      expect(entry.mode, EntryMode.freeform);
      expect(entry.rawText, 'a day');
      expect(entry.feelingSource, FeelingSource.confirmed);
      expect(entry.version, 4);
    });

    test('an unparseable created_at falls back to epoch UTC', () {
      final entry = entryFromJson(
        baseJson(overrides: {'created_at': 'not-a-timestamp'}),
        catalog,
      );
      expect(entry.createdAt, DateTime.utc(1970));
    });

    test('feeling_key resolves the primary feeling', () {
      final entry = entryFromJson(
        baseJson(overrides: {'feeling_key': 'happy'}),
        catalog,
      );
      expect(entry.feeling, happy);
    });

    test('an absent feeling_key leaves feeling null', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.feeling, isNull);
    });

    test('feeling_keys resolves the full set, in order', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'feeling_key': 'sad',
            'feeling_keys': ['sad', 'happy'],
          },
        ),
        catalog,
      );
      expect(entry.feelings, [sad, happy]);
    });

    test('an empty feeling_keys falls back to the single feeling_key', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {'feeling_key': 'happy', 'feeling_keys': <String>[]},
        ),
        catalog,
      );
      expect(entry.feelings, [happy]);
    });

    test('no feeling_key and no feeling_keys leaves feelings empty', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.feelings, isEmpty);
    });

    test('unknown feeling keys are dropped, not invented', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'feeling_key': 'happy',
            'feeling_keys': ['happy', 'invented'],
          },
        ),
        catalog,
      );
      expect(entry.feelings, [happy]);
    });

    test('feeling_intensity absent means never rated, not zero', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.feelingIntensity, isNull);
    });

    test('feeling_intensity is carried when present', () {
      final entry = entryFromJson(
        baseJson(overrides: {'feeling_intensity': 3}),
        catalog,
      );
      expect(entry.feelingIntensity, 3);
    });

    test('feeling_intensities defaults to empty', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.feelingIntensities, isEmpty);
    });

    test('feeling_intensities is carried when present', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'feeling_intensities': {'happy': 4, 'sad': 2},
          },
        ),
        catalog,
      );
      expect(entry.feelingIntensities, {'happy': 4, 'sad': 2});
    });

    test('guided_answers absent decodes to empty', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.guidedAnswers, isEmpty);
    });

    test('guided_answers null decodes to empty', () {
      final entry = entryFromJson(
        baseJson(overrides: {'guided_answers': null}),
        catalog,
      );
      expect(entry.guidedAnswers, isEmpty);
    });

    test('guided_answers are decoded with their wording snapshot', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'guided_answers': [
              {
                'question_key': 'q1',
                'question_text': 'How was your day?',
                'answer_text': 'Good.',
                'order_index': 2,
              },
            ],
          },
        ),
        catalog,
      );
      final answer = entry.guidedAnswers.single;
      expect(answer.questionKey, 'q1');
      expect(answer.questionText, 'How was your day?');
      expect(answer.answerText, 'Good.');
    });

    test('a guided answer missing order_index still decodes', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'guided_answers': [
              {'question_key': 'q1', 'question_text': 'Q', 'answer_text': 'A'},
            ],
          },
        ),
        catalog,
      );
      expect(entry.guidedAnswers.single.answerText, 'A');
    });

    test('suggested_feeling resolves through the catalog', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'suggested_feeling': {'key': 'happy', 'confidence': 0.75},
          },
        ),
        catalog,
      );
      expect(entry.suggestedFeeling?.feeling, happy);
      expect(entry.suggestedFeeling?.confidence, 0.75);
    });

    test('suggested_feeling drops to null for an unknown key', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'suggested_feeling': {'key': 'invented', 'confidence': 0.5},
          },
        ),
        catalog,
      );
      expect(entry.suggestedFeeling, isNull);
    });

    test('suggested_feeling absent is null', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.suggestedFeeling, isNull);
    });

    test('suggested_feelings defaults to empty', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.suggestedFeelings, isEmpty);
    });

    test('suggested_feelings drops unknown keys', () {
      final entry = entryFromJson(
        baseJson(
          overrides: {
            'suggested_feelings': [
              {'key': 'happy', 'confidence': 0.9},
              {'key': 'invented', 'confidence': 0.4},
            ],
          },
        ),
        catalog,
      );
      expect(entry.suggestedFeelings.map((s) => s.feeling.key), ['happy']);
    });

    test('analysis_pending defaults to false', () {
      final entry = entryFromJson(baseJson(), catalog);
      expect(entry.analysisPending, isFalse);
    });

    test('analysis_pending is carried when present', () {
      final entry = entryFromJson(
        baseJson(overrides: {'analysis_pending': true}),
        catalog,
      );
      expect(entry.analysisPending, isTrue);
    });

    test('version is required, with no default', () {
      final json = baseJson()..remove('version');
      expect(() => entryFromJson(json, catalog), throwsA(anything));
    });

    test('mode guided decodes to guided', () {
      final entry = entryFromJson(
        baseJson(overrides: {'mode': 'guided'}),
        catalog,
      );
      expect(entry.mode, EntryMode.guided);
    });
  });
}
