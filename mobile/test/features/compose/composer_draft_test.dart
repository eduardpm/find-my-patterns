import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/features/compose/composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ComposerDraftMode', () {
    test('fromId resolves known ids', () {
      expect(ComposerDraftMode.fromId('guided'), ComposerDraftMode.guided);
      expect(ComposerDraftMode.fromId('freeform'), ComposerDraftMode.freeform);
    });

    test('fromId returns null for anything else, including null', () {
      expect(ComposerDraftMode.fromId('scribbled'), isNull);
      expect(ComposerDraftMode.fromId(null), isNull);
    });
  });

  group('composerDraftHasContent', () {
    test('is false for a fresh guided draft with nothing typed', () {
      expect(
        composerDraftHasContent(
          mode: ComposerDraftMode.guided,
          guidedStepIndex: 0,
          guidedAnswers: const {},
          freeformText: '',
        ),
        isFalse,
      );
    });

    test('is true once a guided answer has non-blank text', () {
      expect(
        composerDraftHasContent(
          mode: ComposerDraftMode.guided,
          guidedStepIndex: 0,
          guidedAnswers: const {'general': 'Feeling okay.'},
          freeformText: '',
        ),
        isTrue,
      );
    });

    test('is false when every guided answer is blank or whitespace', () {
      expect(
        composerDraftHasContent(
          mode: ComposerDraftMode.guided,
          guidedStepIndex: 0,
          guidedAnswers: const {'general': '   '},
          freeformText: '',
        ),
        isFalse,
      );
    });

    test('is true once freeform text is non-blank', () {
      expect(
        composerDraftHasContent(
          mode: ComposerDraftMode.freeform,
          guidedStepIndex: 0,
          guidedAnswers: const {},
          freeformText: 'A long day.',
        ),
        isTrue,
      );
    });

    test(
      'a guided step reached past the first counts even with every answer '
      'now blank -- reaching it required an answer that may since have '
      'been cleared',
      () {
        expect(
          composerDraftHasContent(
            mode: ComposerDraftMode.guided,
            guidedStepIndex: 1,
            guidedAnswers: const {},
            freeformText: '',
          ),
          isTrue,
        );
      },
    );

    test(
      'freeform ignores the step index -- it is a guided-only concept',
      () {
        expect(
          composerDraftHasContent(
            mode: ComposerDraftMode.freeform,
            guidedStepIndex: 3,
            guidedAnswers: const {},
            freeformText: '',
          ),
          isFalse,
        );
      },
    );
  });

  group('ComposerDraft', () {
    test('hasContent delegates to composerDraftHasContent', () {
      final empty = ComposerDraft(
        mode: ComposerDraftMode.guided,
        savedAt: DateTime.utc(2026),
      );
      final withAnAnswer = ComposerDraft(
        mode: ComposerDraftMode.guided,
        guidedAnswers: const {'general': 'Okay.'},
        savedAt: DateTime.utc(2026),
      );
      expect(empty.hasContent, isFalse);
      expect(withAnAnswer.hasContent, isTrue);
    });

    test('toJson/fromJson round-trips every field', () {
      final draft = ComposerDraft(
        mode: ComposerDraftMode.guided,
        guidedStepIndex: 2,
        guidedAnswers: const {'general': 'Okay.', 'work': 'Busy.'},
        freeformText: 'carried text',
        savedAt: DateTime.utc(2026, 8, 28, 23, 32),
      );

      final restored = ComposerDraft.fromJson(draft.toJson());

      expect(restored, isNotNull);
      expect(restored!.mode, ComposerDraftMode.guided);
      expect(restored.guidedStepIndex, 2);
      expect(restored.guidedAnswers, {'general': 'Okay.', 'work': 'Busy.'});
      expect(restored.freeformText, 'carried text');
      expect(restored.savedAt, DateTime.utc(2026, 8, 28, 23, 32));
    });

    test('fromJson returns null for an unrecognised mode', () {
      expect(
        ComposerDraft.fromJson({
          'mode': 'scribbled',
          'saved_at': DateTime.utc(2026).toIso8601String(),
        }),
        isNull,
      );
    });

    test('fromJson returns null when saved_at is missing or unparsable', () {
      expect(ComposerDraft.fromJson({'mode': 'freeform'}), isNull);
      expect(
        ComposerDraft.fromJson({
          'mode': 'freeform',
          'saved_at': 'not a date',
        }),
        isNull,
      );
    });

    test('fromJson defaults absent fields rather than throwing', () {
      final restored = ComposerDraft.fromJson({
        'mode': 'freeform',
        'saved_at': DateTime.utc(2026).toIso8601String(),
      });
      expect(restored, isNotNull);
      expect(restored!.guidedStepIndex, 0);
      expect(restored.guidedAnswers, isEmpty);
      expect(restored.freeformText, '');
    });
  });

  group('SharedPreferencesComposerDraftStore', () {
    const store = SharedPreferencesComposerDraftStore(prefix: 'test');

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load returns null on a fresh install', () async {
      expect(await store.load(), isNull);
    });

    test('round-trips a saved draft', () async {
      final draft = ComposerDraft(
        mode: ComposerDraftMode.guided,
        guidedStepIndex: 1,
        guidedAnswers: const {'general': 'Okay.'},
        savedAt: DateTime.utc(2026, 8, 28, 23, 32),
      );

      await store.save(draft);
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.mode, ComposerDraftMode.guided);
      expect(loaded.guidedStepIndex, 1);
      expect(loaded.guidedAnswers, {'general': 'Okay.'});
      expect(loaded.savedAt, DateTime.utc(2026, 8, 28, 23, 32));
    });

    test('clear removes a saved draft', () async {
      await store.save(
        ComposerDraft(
          mode: ComposerDraftMode.freeform,
          savedAt: DateTime.utc(2026),
        ),
      );

      await store.clear();

      expect(await store.load(), isNull);
    });

    test('a value this build cannot parse reads back as no draft', () async {
      SharedPreferences.setMockInitialValues({
        'test.composer_draft': 'not json at all',
      });
      expect(await store.load(), isNull);
    });

    test('the prefix keeps two apps apart on one device', () async {
      const other = SharedPreferencesComposerDraftStore(prefix: 'other');
      await store.save(
        ComposerDraft(
          mode: ComposerDraftMode.freeform,
          savedAt: DateTime.utc(2026),
        ),
      );

      expect(await other.load(), isNull);
    });

    test('defaults the prefix to the app storage prefix', () {
      expect(
        const SharedPreferencesComposerDraftStore().prefix,
        AppConfig.storagePrefix,
      );
    });
  });
}
