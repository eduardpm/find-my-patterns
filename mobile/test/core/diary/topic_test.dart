import 'package:find_my_patterns/core/diary/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TopicDetail', () {
    test('holds its fields', () {
      const topic = TopicDetail('t1', 'exercise', ['gym'], 12);
      expect(topic.id, 't1');
      expect(topic.name, 'exercise');
      expect(topic.aliases, ['gym']);
      expect(topic.entryCount, 12);
    });
  });

  group('topicDetailFromJson', () {
    test('decodes every field', () {
      final topic = topicDetailFromJson({
        'id': 't1',
        'name': 'exercise',
        'aliases': ['gym', 'workout'],
        'entry_count': 12,
      });
      expect(topic.id, 't1');
      expect(topic.name, 'exercise');
      expect(topic.aliases, ['gym', 'workout']);
      expect(topic.entryCount, 12);
    });

    test('aliases defaults to empty', () {
      final topic = topicDetailFromJson({'id': 't1', 'name': 'exercise'});
      expect(topic.aliases, isEmpty);
    });

    test('entry_count defaults to 0', () {
      final topic = topicDetailFromJson({'id': 't1', 'name': 'exercise'});
      expect(topic.entryCount, 0);
    });
  });
}
