import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/diary_audio_recorder.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// The recorder's three states, mapped straight onto what is on screen.
enum _RecorderPhase {
  /// Nothing is happening; the mic button is offered.
  idle,

  /// Capturing audio.
  recording,

  /// The recording has been uploaded and the backend is transcribing it.
  transcribing,
}

/// Records a spoken answer, has the backend transcribe it, and **appends**
/// the transcript to the field the caller owns.
///
/// Appended, never replacing what is already there: speaking is an
/// addition to an answer, not a replacement for it, and someone who types a
/// sentence and then dictates the rest should end up with both halves.
///
/// [onBusyChange] lets the surrounding flow disable "Next"/"Save" while a
/// recording is still being transcribed — advancing mid-transcription would
/// drop the words on the floor.
class VoiceAnswerRecorder extends ConsumerStatefulWidget {
  /// Builds a recorder that calls [onTranscript] with each transcribed
  /// answer.
  const VoiceAnswerRecorder({
    super.key,
    required this.onTranscript,
    this.onBusyChange,
    this.recorder,
    this.transcriptionDelay = Future.delayed,
  });

  /// Called with the trimmed transcript once a recording has been
  /// successfully transcribed.
  final ValueChanged<String> onTranscript;

  /// Called whenever recording or transcribing starts or stops, so the
  /// caller can disable its own advance/save action while this is busy.
  final ValueChanged<bool>? onBusyChange;

  /// The recorder to use. Defaults to the real device microphone; a test
  /// injects one built over a fake plugin.
  final DiaryAudioRecorder? recorder;

  /// Injected into `TranscriptionsApi.transcribe`'s poll loop, so a test
  /// never waits on a real clock.
  final Future<void> Function(Duration) transcriptionDelay;

  @override
  ConsumerState<VoiceAnswerRecorder> createState() =>
      _VoiceAnswerRecorderState();
}

class _VoiceAnswerRecorderState extends ConsumerState<VoiceAnswerRecorder> {
  late final DiaryAudioRecorder _recorder =
      widget.recorder ?? DiaryAudioRecorder();

  _RecorderPhase _phase = _RecorderPhase.idle;
  String? _error;

  @override
  void dispose() {
    // Leaving the screen mid-recording must not leave the microphone open.
    // A no-op once a recording has already been stopped or never started.
    unawaited(_recorder.cancel());
    super.dispose();
  }

  void _setPhase(_RecorderPhase phase) {
    if (!mounted) return;
    setState(() => _phase = phase);
    widget.onBusyChange?.call(phase != _RecorderPhase.idle);
  }

  Future<void> _startRecording() async {
    setState(() => _error = null);
    try {
      await _recorder.start();
    } on MicrophonePermissionDenied {
      if (!mounted) return;
      setState(
        () => _error = 'Microphone access is needed to record an answer.',
      );
      return;
    } on MicrophoneUnavailable {
      if (!mounted) return;
      setState(() => _error = 'The microphone could not be started.');
      return;
    }
    _setPhase(_RecorderPhase.recording);
  }

  Future<void> _stopRecording() async {
    _setPhase(_RecorderPhase.transcribing);
    final file = await _recorder.stop();
    if (file == null) {
      if (!mounted) return;
      setState(() => _error = 'That recording was too short.');
      _setPhase(_RecorderPhase.idle);
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      final transcript = await ref
          .read(transcriptionsApiProvider)
          .transcribe(
            bytes,
            DiaryAudioRecorder.contentType,
            delay: widget.transcriptionDelay,
          );
      if (!mounted) return;
      final trimmed = transcript.trim();
      if (trimmed.isEmpty) {
        setState(() => _error = 'Nothing could be heard in that recording.');
      } else {
        widget.onTranscript(trimmed);
      }
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      // The recording is the user's own words; it has served its purpose
      // once transcribed (or once transcription has failed for good).
      await _safeDelete(file);
      _setPhase(_RecorderPhase.idle);
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort: nothing depends on this file existing any more.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (_phase) {
      _RecorderPhase.recording => 'Recording.',
      _RecorderPhase.transcribing => 'Transcribing your recording.',
      _RecorderPhase.idle => null,
    };
    final message = _error ?? status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(),
        if (message != null) ...[
          const SizedBox(height: JournalSpacing.x2),
          // Status and errors are announced, not merely shown: someone
          // dictating an answer is by definition not necessarily looking
          // at the screen.
          Semantics(
            liveRegion: true,
            label: message,
            child: ExcludeSemantics(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _error != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildButton() => switch (_phase) {
    _RecorderPhase.transcribing => SecondaryPillButton(
      onPressed: null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: JournalSpacing.x2),
          const Text('Transcribing…'),
        ],
      ),
    ),
    _RecorderPhase.recording => SecondaryPillButton(
      onPressed: _stopRecording,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RecordingDot(),
          const SizedBox(width: JournalSpacing.x2),
          const Text('Stop recording'),
        ],
      ),
    ),
    _RecorderPhase.idle => SecondaryPillButton(
      onPressed: _startRecording,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 18),
          SizedBox(width: JournalSpacing.x2),
          Text('Speak instead'),
        ],
      ),
    ),
  };
}

/// The pulsing dot that marks "this is live".
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 1,
      end: 0.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear)),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}
