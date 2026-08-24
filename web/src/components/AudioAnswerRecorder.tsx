import { useEffect, useRef, useState } from 'react';
import { transcribeAudio } from '../api/transcriptions';
import { Icon } from './Icon';

const MAX_RECORDING_MS = 5 * 60 * 1000;

interface Props {
  draftKey: string;
  questionKey: string;
  orderIndex: number;
  disabled?: boolean;
  onTranscript: (transcript: string) => void;
  onBusyChange?: (busy: boolean) => void;
  onPendingChange?: (pending: boolean) => void;
}

type RecorderState = 'idle' | 'requesting' | 'recording' | 'transcribing' | 'failed';

function preferredMimeType(): string | undefined {
  const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/mp4'];
  return candidates.find((type) => MediaRecorder.isTypeSupported(type));
}

/** Records one answer in memory, sends it to local transcription, then discards the audio Blob. */
export function AudioAnswerRecorder({
  draftKey,
  questionKey,
  orderIndex,
  disabled = false,
  onTranscript,
  onBusyChange,
  onPendingChange,
}: Props) {
  const [state, setState] = useState<RecorderState>('idle');
  const [error, setError] = useState('');
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recordingRef = useRef<Blob | null>(null);
  const recordingUrlRef = useRef('');
  const limitTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mountedRef = useRef(true);
  const [recordingUrl, setRecordingUrl] = useState('');

  const supported =
    typeof MediaRecorder !== 'undefined' && navigator.mediaDevices?.getUserMedia !== undefined;
  const busy = ['requesting', 'recording', 'transcribing'].includes(state);

  useEffect(() => {
    onBusyChange?.(busy);
  }, [busy, onBusyChange]);

  useEffect(() => {
    onPendingChange?.(recordingRef.current !== null);
  }, [recordingUrl, onPendingChange]);

  useEffect(
    () => () => {
      mountedRef.current = false;
      if (limitTimerRef.current) clearTimeout(limitTimerRef.current);
      const recorder = recorderRef.current;
      if (recorder && recorder.state !== 'inactive') {
        recorder.onstop = null;
        recorder.stop();
      }
      streamRef.current?.getTracks().forEach((track) => track.stop());
      if (recordingUrlRef.current) URL.revokeObjectURL(recordingUrlRef.current);
    },
    [],
  );

  function releaseMicrophone() {
    if (limitTimerRef.current) clearTimeout(limitTimerRef.current);
    limitTimerRef.current = null;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }

  function retainRecording(recording: Blob) {
    recordingRef.current = recording;
    setRecordingUrl((previous) => {
      if (previous) URL.revokeObjectURL(previous);
      const next = URL.createObjectURL(recording);
      recordingUrlRef.current = next;
      return next;
    });
  }

  function discardRecording() {
    recordingRef.current = null;
    setRecordingUrl((previous) => {
      if (previous) URL.revokeObjectURL(previous);
      recordingUrlRef.current = '';
      return '';
    });
    setError('');
    setState('idle');
  }

  async function upload(recording: Blob) {
    releaseMicrophone();
    if (recording.size === 0) {
      setError('The recording was empty. Please try again.');
      setState('idle');
      return;
    }

    setState('transcribing');
    const result = await transcribeAudio(recording, draftKey, questionKey, orderIndex);
    if (!mountedRef.current) return;
    if (result.ok) {
      onTranscript(result.value);
      discardRecording();
    } else {
      setError(`${result.error.message} Your recording is still available below.`);
      setState('failed');
    }
  }

  function finishRecording(mimeType: string) {
    const recording = new Blob(chunksRef.current, { type: mimeType || 'audio/webm' });
    if (recording.size === 0) {
      releaseMicrophone();
      setError('The recording was empty. Please try again.');
      setState('idle');
      return;
    }
    retainRecording(recording);
    void upload(recording);
  }

  async function start() {
    if (!supported || disabled || busy) return;
    setError('');
    setState('requesting');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!mountedRef.current) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      streamRef.current = stream;
      chunksRef.current = [];
      const mimeType = preferredMimeType();
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      recorderRef.current = recorder;
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      };
      recorder.onstop = () => finishRecording(recorder.mimeType);
      recorder.start();
      setState('recording');
      limitTimerRef.current = setTimeout(() => recorder.stop(), MAX_RECORDING_MS);
    } catch {
      releaseMicrophone();
      setError('Microphone access was not available. Check your browser permission and try again.');
      setState('idle');
    }
  }

  function stop() {
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop();
  }

  function retry() {
    if (recordingRef.current) void upload(recordingRef.current);
  }

  if (!supported) {
    return <p className="muted">Audio recording is not supported by this browser.</p>;
  }

  return (
    <div className="audio-answer">
      {state === 'recording' ? (
        <button type="button" className="btn btn--recording" onClick={stop}>
          <span className="recording-dot" aria-hidden="true" />
          Stop recording
        </button>
      ) : state !== 'failed' ? (
        <button
          type="button"
          className="btn btn--secondary"
          onClick={() => void start()}
          disabled={disabled || busy}
        >
          <Icon name="mic" />
          {state === 'requesting'
            ? 'Opening microphone…'
            : state === 'transcribing'
              ? 'Transcribing…'
              : 'Record answer'}
        </button>
      ) : null}
      {/*
        The reassurance about the audio being discarded is the whole reason a private diary can ask
        for a microphone at all, so it is a persistent hint attached to the control rather than a
        transient message.
      */}
      <span className="field-hint" role="status">
        {state === 'recording'
          ? 'Listening…'
          : state === 'transcribing'
            ? 'Turning your recording into text locally…'
            : 'Audio is discarded after transcription.'}
      </span>
      {error && (
        <p className="audio-answer__error" role="alert">
          {error}
        </p>
      )}
      {state === 'failed' && recordingUrl && (
        <div className="audio-answer__recovery">
          <audio controls src={recordingUrl} aria-label="Your saved recording" />
          <div className="row">
            <button type="button" className="btn btn--secondary" onClick={retry}>
              <Icon name="refresh" />
              Retry transcription
            </button>
            <a className="btn btn--text" href={recordingUrl} download="diary-answer.webm">
              Download recording
            </a>
            <button type="button" className="btn btn--text" onClick={discardRecording}>
              <Icon name="trash" />
              Discard recording
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
