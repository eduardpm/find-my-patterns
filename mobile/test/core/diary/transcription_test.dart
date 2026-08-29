import 'package:find_my_patterns/core/diary/transcription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptionStatus', () {
    test('fromWire resolves the known statuses', () {
      expect(
        TranscriptionStatus.fromWire('pending'),
        TranscriptionStatus.pending,
      );
      expect(
        TranscriptionStatus.fromWire('completed'),
        TranscriptionStatus.completed,
      );
      expect(
        TranscriptionStatus.fromWire('failed'),
        TranscriptionStatus.failed,
      );
    });

    test('fromWire falls back to pending', () {
      expect(
        TranscriptionStatus.fromWire('anything_else'),
        TranscriptionStatus.pending,
      );
      expect(TranscriptionStatus.fromWire(null), TranscriptionStatus.pending);
    });
  });

  group('TranscriptionJob', () {
    test('holds status, transcript and error', () {
      const completed = TranscriptionJob(
        TranscriptionStatus.completed,
        transcript: 'hello',
      );
      const failed = TranscriptionJob(
        TranscriptionStatus.failed,
        error: 'boom',
      );
      const pending = TranscriptionJob(TranscriptionStatus.pending);

      expect(completed.transcript, 'hello');
      expect(completed.error, isNull);
      expect(failed.error, 'boom');
      expect(pending.transcript, isNull);
      expect(pending.error, isNull);
    });
  });
}
