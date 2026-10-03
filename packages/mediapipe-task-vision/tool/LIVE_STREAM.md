# Streaming modes (planned)

**Status:** planned, not started. This note covers the three streaming
pieces the repository lacks, which share one design: vision's LIVE_STREAM
split from VIDEO, a video file mode in the gallery so VIDEO has a demo of its
own, and the audio stream mode. Camera frames run in VIDEO mode today, and
`RunningMode.liveStream` and `AudioRunningMode.audioStream` throw
`UnsupportedError` when a task is created. Each code site to revisit carries
a TODO, starting with the ones on `RunningMode.liveStream` and
`AudioRunningMode.audioStream`; `git grep -n "TODO.*LIVE_STREAM"` and
`git grep -n "TODO.*audio stream"` list them. Reviewed on 2026-10-03 against
Google's v1.0.0 source and the code as of main `418efdf`.

## Google's three vision modes

Checked on 2026-10-01 against the MediaPipe v1.0.0 source (`6d31f1e`):

| | IMAGE | VIDEO | LIVE_STREAM |
| --- | --- | --- | --- |
| Call | Blocks | Blocks until the graph is idle | Returns at once; the result arrives in a callback on a MediaPipe thread |
| Stream mode (tracking, smoothing) | Off | On | On |
| Frame dropping | None | None: every frame is processed | One frame in flight, one queued; a newer frame replaces the queued one, and dropped frames get no callback |

- Every camera-capable vision task turns on stream mode for any mode other than
  IMAGE
  ([face_landmarker.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/cc/vision/face_landmarker/face_landmarker.cc#L108)),
  so tracking and smoothing are the same in VIDEO and LIVE_STREAM.
- LIVE_STREAM's only change to the graph is a `FlowLimiterCalculator` in front
  of the task, with `max_in_flight: 1` and `max_in_queue: 1`
  ([utils.h](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/cc/core/utils.h#L85)).
  The calculator's header explains why: the graph never sits idle and the queue
  always holds the newest frame, while a queue of 0 lowers latency but costs
  frame rate
  ([flow_limiter_calculator.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/calculators/core/flow_limiter_calculator.cc#L38)).
  When the queue is over its limit it discards from the front, so the newest
  frame survives and the older queued one is the one dropped.
- VIDEO calls `TaskRunner::Process`, which waits for the graph to go idle.
  LIVE_STREAM calls `TaskRunner::Send`, which returns immediately
  ([task_runner.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/cc/core/task_runner.cc#L241)).
  Both reject a timestamp that is not greater than the last one, and `Send`
  records the timestamp before the limiter sees the frame, so a frame that is
  later dropped still takes its timestamp: the next frame must be newer than
  it. Timestamps are milliseconds at every API and microseconds inside.
- `Send` reports the wrong mode and a bad timestamp synchronously; a failure
  inside the graph reaches the callback as an error status, after which the
  graph is unusable.
- `TaskRunner::Close` closes the input streams and waits for the graph to
  finish. The limiter releases its queued frame when the in-flight one
  reports finished, so closing processes the in-flight frame and the queued
  one, and their results arrive during the close.
- The web tasks have no LIVE_STREAM: `RunningMode = 'IMAGE'|'VIDEO'`
  ([vision_task_options.d.ts](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/web/vision/core/vision_task_options.d.ts#L24)),
  and `detectForVideo` runs synchronously inside the WASM worker.
- The Android SDK's `detectAsync(image, options, timestampMs)` requires
  `setResultListener` (and `setErrorListener`) when the task is created in
  LIVE_STREAM, converts milliseconds to microseconds, and throws
  `IllegalArgumentException` for a region of interest on the tasks that take
  none; the iOS SDK's `detectAsync(image:timestampInMilliseconds:)` delivers
  to a `LiveStreamDelegate` on a serial dispatch queue the runner owns.
- Only Image Classifier and Image Embedder accept a region of interest, in
  every mode; Interactive Segmenter has no modes.

## This repository today

- The VIDEO methods (`detectForVideo`, `recognizeForVideo`, ...) serve both
  decoded video and cameras.
- `VisionTaskChecks` is the one set of checks on every platform: mode,
  rotation, timestamps (nonnegative, strictly increasing, at most
  JavaScript's exact integer range in microseconds, about 285 years),
  disposal, and a failure that poisons every later call. The results carry
  `timestampMilliseconds`, null for still images.
- The package never drops a frame. `VisionTaskWorker` (Google's native
  runtime on a worker isolate; each `VisionTaskInput` crosses a `SendPort`,
  pixels copied), the Android plugin's `TaskHost` worker (pixels or a path
  cross the method channel per frame) and the web worker (an `ImageBitmap`
  transferred per frame, closed after inference) run every request in order,
  so a caller that submits each camera frame without awaiting falls further
  and further behind.
- The gallery rebuilds Google's policy by hand (one in flight, the newest one
  pending) in `gallery/lib/live/live_camera_controller_native.dart` and
  `gallery/lib/web/live_camera_controller.dart`, counting `skippedFrames`.
  The vision example skips every frame that arrives while it is busy, which
  is a queue of 0. The gallery converts a camera frame (YUV to RGBA on
  Android; `createImageBitmap(video)` on the web) only when the frame starts.
- The native gallery controller stamps a pending frame when it starts, not when
  it arrived, from a `Stopwatch` with an offset that keeps timestamps
  increasing across delegate switches. Google's API takes the timestamp at
  submission.
- The tests read these counters: `sdk_face_landmarker_test.dart` and
  `sdk_hand_landmarker_test.dart` wait for `processedFrames` (20 and 10),
  `real_camera_test.dart` reports `processed_frames` and `skipped_frames`,
  the desktop camera tests watch `processedFrames`, and the journey watches
  `recentFrames`.
- The gallery has one live page with two input modes, camera and still image.
  Nothing in the repository decodes a video file: the README documents VIDEO
  for "decoded video", but no demo feeds one, so the gallery shows what
  LIVE_STREAM is for and nothing that shows what VIDEO is for.

## Design: `RunningMode.liveStream`

The public API, the same on all six platforms:

- Creation takes `runningMode: RunningMode.liveStream` with the task's usual
  options; nothing else changes, and the web creates it too.
- One submission method per task, named as Google names them: `detectAsync`
  (Face Detector, Face, Hand, Pose and Holistic Landmarker, Object Detector),
  `recognizeAsync` (Gesture Recognizer), `classifyAsync` (Image Classifier),
  `embedAsync` (Image Embedder) and `segmentAsync` (Image Segmenter). Each
  takes `(VisionImage image, {required int timestampMilliseconds, int
  rotationDegrees = 0})`, plus `regionOfInterest` on the two tasks that
  accept one, and returns `void`: the checks throw synchronously, the frame
  then belongs to the task. A dropped frame produces nothing, as in Google's
  runtime, and `droppedFrames` counts them for the caller's statistics.
- `Stream<R> get results` delivers the results in timestamp order, each
  carrying its frame's `timestampMilliseconds`, with the contract the text
  package's streams already have: one subscription, pausing buffers, errors
  as `TaskException`. The listener must be in place before the first
  submission, as Google requires a result listener at creation: a submission
  without one throws `StateError`. Cancelling the subscription discards later
  results; frames keep being processed until disposal.
- A failed frame delivers its `TaskException` on `results`, closes the
  stream and poisons the task as `VisionTaskChecks.failure` does today: later
  submissions throw the same error; `dispose` still releases the runtime.
- `dispose()` stops accepting frames, waits for the in-flight frame,
  processes the queued one and delivers both results, then closes `results`,
  matching Google's close. It is idempotent, and a submission after it
  throws `StateError`.

How it works:

1. Emulate on Google's VIDEO graph, with the limiter in Dart. Every frame
   that gets processed has the same result as under native LIVE_STREAM, since
   both modes turn on the same tracking and smoothing and only the limiter's
   location differs. One implementation covers all six platforms, including
   the web, which has no LIVE_STREAM. The backend task is created in VIDEO
   mode under the hood: `nativeRunningMode` and the Android and web adapters
   map `liveStream` to VIDEO, and the iOS bridge's `Configure` is unchanged.
2. The limiter lives in `VisionTaskRunner`, which both the native worker and
   the SDK adapters go through: one in flight, one queued, a newer frame
   replaces the queued one and the replaced one is dropped. Dropping happens
   on the caller's isolate before any copy: no `SendPort` message for the
   native worker, no method-channel call on Android, and on the web the
   dropped frame's `ImageBitmap` is closed by the package, since the backend
   only releases frames it ran.
3. Timestamps are checked and reserved at submission for every frame, dropped
   or not, with the shared rules in `VisionTaskChecks`; a `liveStream` check
   joins `image` and `video` there. The caller stamps at arrival; the
   gallery's start-time stamping goes.
4. Frames stay cheap to drop. With the newest frame always queued, every
   frame that arrives while the task is busy replaces the queued one, so a
   frame converted before submission is converted for nothing when it is
   replaced. Android camera frames need YUV to RGBA, the web needs
   `createImageBitmap`, iOS and the desktops hand over BGRA or RGBA as they
   are. Measure the conversion cost at camera rate on the Test Lab phones and
   in the browsers first; if it shows, add a lazy image whose pixels are
   produced when the frame starts, and let the gallery pass its conversion
   as that producer. The queued frame keeps its own bytes either way: the
   camera plugin's `CameraImage` planes are Dart copies, so holding one is
   safe.
5. Leave VIDEO unchanged for decoded video, where every frame matters.
6. Move the gallery and the vision example to live stream mode: delete their
   mailboxes and skip logic, stamp at arrival, replace `skippedFrames` with
   the task's `droppedFrames` (the stats chart shows drops per second), and
   update the tests that read the counters (`skipped_frames` becomes
   `dropped_frames` in the measurement lines; the `processedFrames` waits
   stay). Update the README's "Video and live cameras" into "Video files"
   (VIDEO, `detectForVideo`) and "Live cameras" (LIVE_STREAM, `detectAsync`),
   each pointing at the gallery mode that demonstrates it, and note in the
   CHANGELOG that `liveStream` no longer throws.
7. Tests, in the vision package's unit tests with a fake backend and in the
   gallery's device suites against Google's runtime:
   - The same frames processed in LIVE_STREAM and VIDEO give the same results
     (the emulation's defining property), on every platform.
   - Under a slow backend the newest queued frame wins, the replaced frame is
     counted in `droppedFrames`, and no result arrives for it.
   - A dropped frame's timestamp still blocks an older timestamp; a timestamp
     out of range or not increasing throws at submission on every platform
     with the same message.
   - No copy for a dropped frame: the fake native worker and fake channel see
     only accepted frames; on the web the dropped `ImageBitmap` is closed.
   - A frame submitted without a listener throws; pausing buffers; cancelling
     discards.
   - A backend error reaches the listener, closes `results` and poisons later
     submissions.
   - Disposal with a frame in flight and one queued delivers both results and
     then closes `results`; disposal twice is one disposal.
   - The region of interest is accepted by the classifier and embedder only.
8. Give the gallery a video file mode, so the two modes are shown side by
   side: the camera on LIVE_STREAM, a file on VIDEO. The face_detection_tflite
   example is the model: its home screen offers Live Camera, Still Image and
   Video File, and the Video File screen decodes every frame, runs detection
   on each, draws the result and writes the annotated clip, which it then
   plays back. For the gallery:
   - A third input mode on the live page beside camera and still image, for
     every camera-capable vision task. The file's frames go through
     `detectForVideo` with the decoder's presentation timestamps (rounded to
     milliseconds, kept strictly increasing, a duplicate frame skipped), every
     frame processed, results drawn per frame, and the processed clip shown
     as it is produced, with the frame count and time per frame on the status
     line. Play, pause and restart only: VIDEO timestamps cannot go backwards,
     so a seek means a new task. Decode frame by frame, never the whole file
     into memory; cancellation stops mid-file; a file's rotation metadata
     becomes `rotationDegrees` so results come out in display orientation;
     decoder output (NV12, YUV420, BGRA, 10-bit HDR) is converted to 8-bit
     RGBA with the camera path's conversion; audio tracks are ignored; a
     resolution change mid-file needs nothing, since every frame carries its
     own size.
   - A frame source per platform, which is the work. That example reads with
     OpenCV's `VideoCapture` (the `dartcv`/`opencv_dart` package) on
     Android, iOS and the desktops and writes with its `VideoWriter`; that
     adds a large native dependency to the gallery, so measure its size per
     platform and weigh it against a small decoding plugin over the platform
     decoders (AVAssetReader on Apple platforms, MediaExtractor and MediaCodec
     on Android, Media Foundation's source reader on Windows, GStreamer or
     ffmpeg on Linux). `video_player` renders to a texture and gives no
     frames; ffmpeg_kit is retired. In browsers a `<video>` element plays the
     file, and since `requestVideoFrameCallback` only reports the frames the
     browser presented, step the playback with `seek` per frame (from the
     clip's frame rate, with `mediaTime` as the timestamp) so no frame is
     skipped; WebCodecs' `VideoDecoder` would need a demuxer and newer
     browsers. The package stays decoder-free: apps bring frames.
   - A bundled sample clip of a few seconds (a face, hands and a body in one
     short scene, H.264 so every platform and browser decodes it, a few
     megabytes) beside the sample images, listed in the manifest like them,
     so every platform's journey test can open the mode, process the whole
     clip and check that every frame produced a result and that the
     timestamps increased strictly.

### Native LIVE_STREAM, if profiling asks for it

The public API is the same either way, so a platform can move to native later.
The copy problem the C API poses is already solved once in this repository:
the text package compiles `native/text_stream_bridge.c` with its build hook,
Google's callback copies each result inside the callback into a struct Dart
owns, and a `NativeCallable.listener` receives the copy and frees it
(`packages/mediapipe-task-text/lib/src/io/native_text_stream.dart`). Vision
would do the same per task, copying landmarks, categories, detections and the
segmenter's masks, which are valid only during the callback. Going native,
platform by platform:

- **Desktop:** Google's C library exports `MpFaceLandmarkerDetectAsync` and the
  other `*Async` calls, with the callback on a MediaPipe thread and arguments
  valid only during the call
  ([face_landmarker.h](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h#L92)).
  Google's Python wrapper copies the same way inside its ctypes callback
  ([async_result_dispatcher.py](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/python/core/async_result_dispatcher.py#L146)).
  `nativeRunningMode`, plus the running-mode mappings in
  `native_face_detector.dart`, `native_face_landmarker.dart` and
  `native_object_detector.dart`, would map the new mode.
- **iOS:** `packages/mediapipe-core/native/ios/vision_sdk_bridge.mm` already
  copies results into C structs, but its `Configure` rejects LIVE_STREAM. It
  would adopt the SDK's live stream delegates and post copied results to Dart.
- **Android:** `MediaPipeVisionPlugin.java` maps only IMAGE and VIDEO.
  `detectAsync` with a result listener would send results as `update` events
  through core's `TaskHost.emit`, the path the text streams already use.
- **Web:** there is no LIVE_STREAM to call.

What native would buy is not results, which are identical, but possibly
latency on Android and iOS, where the SDK's own pipeline would skip the hop
through the plugin worker. Decide after comparing the emulated mode's frame
times with today's gallery numbers on the Test Lab phones.

## Audio stream mode

Google's audio tasks have their own pair of modes, checked on 2026-10-03
against the same v1.0.0 source:

| | AUDIO_CLIPS | AUDIO_STREAM |
| --- | --- | --- |
| Call | `Classify(clip, sampleRate)` blocks and returns one result per model window the clip is split into | `ClassifyAsync(block, sampleRate, timestampMs)` returns at once; the `result_callback` fires once per window, possibly several times per block |
| Framing | Each clip framed on its own | Blocks accumulated and framed as one continuous signal: a window can straddle two blocks, leftover samples carry into the next block |
| Sample rate | Per call | Fixed by the first block; timestamps must increase |
| Dropping | None | None |

- The only graph difference is `AudioToTensorCalculator`'s `stream_mode`
  ([audio_classifier_graph.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/cc/audio/audio_classifier/audio_classifier_graph.cc#L100)):
  resampling, accumulation and framing across calls, with the model's window
  and overlap from its metadata. YAMNet's window is 15,600 samples at 16 kHz
  with no overlap: the reference fixture's chunks sit at 0, 975, 1950 ms.
  There is no flow limiter: where vision's LIVE_STREAM is about dropping
  frames, the audio stream is about continuity.
- Channels: a model with one channel mixes any input down to mono; otherwise
  the input's channel count must equal the model's
  ([audio_to_tensor_calculator.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/calculators/tensor/audio_to_tensor_calculator.cc#L349)).
- Timestamps follow `TaskRunner::Send`'s rule, strictly increasing. The
  calculator's jitter check (`check_inconsistent_timestamps`) only logs a
  warning when a block's timestamp disagrees with the samples received, so
  a microphone's clock drift does not fail the stream.
- Closing flushes: the resampler's remainder and `padding_samples_after`
  zeros are appended and the tail is processed, so a final short block yields
  one more result during the close (the iOS SDK documents that the last short
  block is processed only when the classifier is closed).
- The C API has `MpAudioClassifierClassifyAsync` and a `result_callback` on
  the options
  ([audio_classifier.h](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/c/audio/audio_classifier/audio_classifier.h#L120)),
  with the same rule as vision's: the callback runs on a MediaPipe thread and
  its arguments are valid only during the call. The Android SDK has
  `classifyAsync(AudioData, timestampMs)`, which fixes the sample rate on the
  first block, with a result listener; the iOS SDK has
  `classifyAsync(audioBlock:timestampInMilliseconds:)` with a stream
  delegate. The web task has only `classify`; Google's TypeScript carries a
  TODO for a `classifyStream`.

This repository today: `AudioRunningMode.audioStream` is reserved and
`AudioClassifier.create` throws for it. The native classifier runs each clip
through `Isolate.run`, with no persistent worker (the text worker is one);
core's iOS audio bridge configures clips mode only; the Android plugin creates
clips mode only; the web worker calls `classify`. The gallery's microphone
mode records at 16 kHz and is hand-rolled on clips mode: it keeps the last
15,600 samples and classifies that window again as audio arrives, so windows
are re-run per update rather than framed continuously, and no window straddles
two updates.

Design, with the vision contract:

- `AudioClassifier.create` with `runningMode: AudioRunningMode.audioStream`;
  `void classifyAsync(AudioData block, {required int timestampMilliseconds})`
  returns at once; `Stream<AudioClassifierResult> get results` delivers one
  result per window with its timestamp, listener required before the first
  block, pausing buffers, cancelling discards, an error closes the stream and
  poisons the task.
- Nothing is dropped: every block is processed in order, so a caller that
  feeds faster than real time only queues memory; blocks may be any length,
  each yielding zero or more results.
- Checked in Dart before the runtime, with one message on every platform: the
  sample rate is fixed by the first block (`ArgumentError` on a change, as
  Google refuses it), a channel count other than the model's is refused
  unless the model is mono, and timestamps follow the shared rules.
- `dispose()` flushes the tail as Google does, delivers whatever that yields,
  then closes `results`.

Emulate or native: emulating on clips mode (accumulate samples in Dart, carry
the leftovers, classify each full window) reproduces Google's framing exactly
when the blocks arrive at the model's rate and the model's windows do not
overlap, which is the gallery's 16 kHz case, and only approximately when the
runtime resamples, since per-window resampling has no state across windows.
Native matches Google in every case: the desktops through
`MpAudioClassifierClassifyAsync` with a copy shim like
`text_stream_bridge.c` (the result copied inside the callback, received by a
`NativeCallable.listener`) on a persistent worker, iOS through the SDK's
stream delegate in core's audio bridge, Android through `classifyAsync` and
its listener emitting `update` events through `TaskHost.emit`. The web stays
emulated, since Google has no stream there; its per-window resampling is the
documented approximation. Recommended: native on the native platforms,
emulated on the web, with the emulation at the model's rate as the oracle
the native path is tested against.

Plan, alongside the vision steps:

1. Implement the API above on every platform, the native path first on the
   desktops, then iOS and Android, then the web emulation.
2. Move the gallery's microphone mode onto it, delete its sliding window, and
   update the audio README's "Keep one classifier for a live stream"
   paragraph to the new mode; note in the CHANGELOG that `audioStream` no
   longer throws.
3. Tests, in the audio package with a fake backend and in the gallery's
   suites against Google's runtime:
   - Continuity: a reference clip fed as 100 ms blocks gives the clip's
     results, timestamps included, on every platform; windows that straddle
     two blocks match the clip's.
   - Block sizes of one sample and of several windows; a stereo stream to the
     mono model equals the mono clip; a changed sample rate and a timestamp
     that does not increase are refused with the shared message, and jitter
     within a block is tolerated.
   - The tail: a lone 500 ms block yields exactly one result on disposal,
     compared with Google's wheel on the desktops.
   - Errors reach the listener and poison the task; pause buffers; cancel
     discards; disposal twice is one disposal.
   - The gallery's microphone mode in the journey: CI has no microphone, so
     the page's stream path takes blocks from the sample WAV through the same
     code, and the journey checks results arrive with increasing timestamps.

## Order of work

1. Vision live stream in the package (emulated), with its tests, README and
   CHANGELOG, then the gallery and example moved onto it; one PR, verified by
   the full CI loop and a Test Lab run for the phones' drop rates.
2. The gallery's video file mode, its own PR, after the decoder decision.
3. The audio stream mode and the gallery's microphone mode, its own PR.

## Open decisions

- Vision: emulated (recommended) or native, decided by the frame-time
  comparison in "Native LIVE_STREAM, if profiling asks for it".
- Whether a lazy `VisionImage` is needed, decided by the conversion
  measurement in step 4.
- The video decoder for the gallery: OpenCV as the face_detection_tflite
  example, or a small plugin over the platform decoders.
