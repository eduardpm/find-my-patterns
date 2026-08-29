import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuestionCategory', () {
    test('fromWire resolves every known category', () {
      expect(QuestionCategory.fromWire('general'), QuestionCategory.general);
      expect(QuestionCategory.fromWire('mind_body'), QuestionCategory.mindBody);
      expect(
        QuestionCategory.fromWire('small_influences'),
        QuestionCategory.smallInfluences,
      );
      expect(
        QuestionCategory.fromWire('response_outcome'),
        QuestionCategory.responseOutcome,
      );
    });

    test('fromWire falls back to unknown', () {
      expect(
        QuestionCategory.fromWire('anything_else'),
        QuestionCategory.unknown,
      );
      expect(QuestionCategory.fromWire(null), QuestionCategory.unknown);
    });
  });

  group('GuidingQuestion', () {
    test('holds its fields', () {
      const question = GuidingQuestion(
        'q1',
        QuestionCategory.general,
        'How was your day?',
        ['day'],
        true,
      );
      expect(question.key, 'q1');
      expect(question.isMandatory, isTrue);
    });
  });

  group('GuidingQuestionAnswer', () {
    test('holds question key and answer text', () {
      const answer = GuidingQuestionAnswer('q1', 'It was fine.');
      expect(answer.questionKey, 'q1');
      expect(answer.answerText, 'It was fine.');
    });
  });

  group('matchingOptionalQuestions', () {
    GuidingQuestion question(
      String key, {
      List<String> keywords = const [],
      bool mandatory = false,
    }) => GuidingQuestion(
      key,
      QuestionCategory.general,
      key,
      keywords,
      mandatory,
    );

    test('blank draft returns nothing', () {
      final library = [
        question('q1', keywords: ['work']),
      ];
      expect(matchingOptionalQuestions('', library), isEmpty);
      expect(matchingOptionalQuestions('   ', library), isEmpty);
    });

    test('empty library returns nothing', () {
      expect(matchingOptionalQuestions('a busy day at work', []), isEmpty);
    });

    test('mandatory questions are never included', () {
      final library = [
        question('mandatory', keywords: ['work'], mandatory: true),
      ];
      expect(matchingOptionalQuestions('busy day at work', library), isEmpty);
    });

    test('a whole-word keyword match surfaces the question', () {
      final library = [
        question('q-work', keywords: ['work']),
      ];
      expect(
        matchingOptionalQuestions(
          'a busy day at work today',
          library,
        ).map((q) => q.key),
        ['q-work'],
      );
    });

    test('a substring keyword match also surfaces the question', () {
      final library = [
        question('q-run', keywords: ['run']),
      ];
      expect(
        matchingOptionalQuestions(
          'went for a running session',
          library,
        ).map((q) => q.key),
        ['q-run'],
      );
    });

    test('keyword matching is case-insensitive', () {
      final library = [
        question('q-work', keywords: ['Work']),
      ];
      expect(
        matchingOptionalQuestions(
          'WORK was hard today',
          library,
        ).map((q) => q.key),
        ['q-work'],
      );
    });

    test('a blank keyword never matches', () {
      final library = [
        question('q-blank', keywords: ['   ']),
      ];
      expect(matchingOptionalQuestions('anything at all', library), isEmpty);
    });

    test('results stay in library order', () {
      final library = [
        question('q-second', keywords: ['gym']),
        question('q-first', keywords: ['work']),
      ];
      expect(
        matchingOptionalQuestions(
          'work and gym today',
          library,
        ).map((q) => q.key),
        ['q-second', 'q-first'],
      );
    });

    test('results are capped at maxCount', () {
      final library = [
        question('q1', keywords: ['work']),
        question('q2', keywords: ['gym']),
        question('q3', keywords: ['sleep']),
      ];
      expect(
        matchingOptionalQuestions(
          'work gym sleep all today',
          library,
        ).map((q) => q.key),
        ['q1', 'q2'],
      );
      expect(
        matchingOptionalQuestions(
          'work gym sleep all today',
          library,
          maxCount: 1,
        ).map((q) => q.key),
        ['q1'],
      );
    });

    test('a question with no matching keyword is excluded', () {
      final library = [
        question('q-work', keywords: ['work']),
      ];
      expect(
        matchingOptionalQuestions('a quiet day at home', library),
        isEmpty,
      );
    });

    test('handles unicode letters in the word split', () {
      final library = [
        question('q-cafe', keywords: ['café']),
      ];
      expect(
        matchingOptionalQuestions(
          'went to a café today',
          library,
        ).map((q) => q.key),
        ['q-cafe'],
      );
    });
  });
}
