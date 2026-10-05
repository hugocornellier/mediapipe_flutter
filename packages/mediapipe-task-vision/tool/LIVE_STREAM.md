# Streaming modes

**Status:** all three streaming pieces have shipped. Vision's live stream
mode, emulated on Google's VIDEO graph on all six platforms, with the gallery
and the vision example on it, and the gallery's video file mode, which shows
VIDEO beside it, are described below ("What shipped"). The audio stream mode,
Google's own stream on Android, iOS, macOS, Linux and Windows and an emulation
in browsers, with the gallery's microphone mode on it, has its own note:
`packages/mediapipe-task-audio/tool/AUDIO_STREAM.md`. This note covers the
three pieces, which share one design: vision's LIVE_STREAM split from VIDEO, a
video file mode in the gallery so VIDEO has a demo of its own, and the audio
stream mode. Reviewed on 2026-10-03 against Google's v1.0.0 source and the
code as of main `418efdf`.

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

## The repository before live stream mode

As of main `418efdf`, before vision's live stream mode shipped:

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
   as that producer (it showed on Android; see Decisions). The queued frame
   keeps its own bytes either way: the camera plugin's `CameraImage` planes
   are Dart copies, so holding one is safe.
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

### What shipped (steps 1 to 7)

- **Package.** `runner/live_stream.dart` holds the limiter
  (`LiveStreamLimiter`), which `VisionTaskRunner` creates for a task opened
  in live stream mode, whichever transport serves it. A submission runs
  `VisionTaskChecks.liveStream` (mode, listener, rotation, timestamp,
  reserved at once) and then starts the frame, queues it or replaces the
  queued one; a started frame goes to the transport without being checked
  again (`SdkVisionTask.liveFrame`, `NativeTaskRunner.processLiveFrame`).
  A replaced frame is counted and, in browsers, its bitmap closed
  (`runner/browser_frames*.dart`). A failed frame sets
  `VisionTaskChecks.failure`, drops the queued frame, delivers the
  `TaskException` and closes `results`. A result reaches the listener before
  the queued frame starts, since a deferred frame is converted when it starts,
  on the same isolate, and would otherwise hold the result back by its
  conversion (the Test Lab run showed it; see Decisions). The native worker used that same
  failure as its sign of a dead isolate and skipped its close request; it now
  keeps its own `_workerFailed`, so a poisoned but living worker still closes
  Google's task. Every adapter maps `liveStream` to VIDEO: `nativeRunningMode`
  and the three tasks with their own mapping (Face Detector, Face Landmarker,
  Object Detector), the Android adapter's `mode` and the web adapter's
  `runningMode`; the Java plugin and the iOS bridge are unchanged.
- **API.** Per task `detectAsync`, `recognizeAsync`, `classifyAsync`,
  `embedAsync` or `segmentAsync`, `results` (which throws `StateError` in the
  other modes) and `droppedFrames` (0 in the other modes); the parity snapshot
  gained exactly these, identical on native and web.
- **Deferred frames.** `VisionImage.deferred(produce)` holds a producer the
  runner calls when the limiter starts the frame (`producedImage`), so the
  worker, the channel and the browser only ever see the produced frame; image
  and video mode and the Interactive Segmenter refuse it
  (`refuseDeferredImage`). A producer's error fails the frame like any other.
- **Gallery.** `LiveTask` lost its VIDEO `detect` and gained `submit`,
  `results` (each result with the timestamp it was submitted with) and
  `droppedFrames`. Both camera controllers stamp and submit every frame as it
  arrives, and keep each frame's arrival time and drawing data by timestamp
  until its result comes. The native controller submits a deferred frame
  whose producer converts the camera image and records when the frame
  started, so inference is the result's time minus that start, and latency
  the result's time minus the arrival. The browser controller converts at
  arrival and does not see a frame start, so it derives it: a frame started
  at its arrival or at the previous result, whichever came later, since the
  limiter starts the queued frame then. The warm-up submits the sample and the
  blank frame one at a time and waits for each result. The Stats legend shows
  the frames dropped per second beside the inference time
  (`SpeedHistory.droppedPerSecond`). The vision example's drop-while-busy (a
  queue of 0) became the task's limiter too.
- **Tests.** `test/live_stream_test.dart`: the plan's list on a fake backend
  through the public classes, the ten tasks' submission methods, and a fake
  native task on a real worker isolate showing dropped frames never reach it.
  `test/live_stream_runtime_test.dart`: the ten tasks on Google's native
  runtime, five frames each (subject, quarter turn, empty frame, subject
  twice), VIDEO and LIVE_STREAM results identical; it runs in `make test`
  on macOS and in `tool/test_desktop.py` on Linux and Windows.
  `test/android_adapter_test.dart`: a live task is created as `video` and only
  the frames that run cross the method channel.
  `test/web/live_stream_web_test.dart`: the dropped bitmaps are closed, in Chrome (JS and WebAssembly). The web API
  probe compares live and VIDEO Face Landmarker results in every browser CI
  runs and checks a dropped bitmap is closed. The gallery's `runtime_test`
  opens every live tile in live stream mode, and the controller tests run the
  package's real limiter behind a scripted backend.

### What shipped (step 8)

- **Decoder.** `gallery/packages/video_frames`, the gallery's own plugin (about
  1,450 lines over six platforms), with one Dart API: `VideoFileReader.open`,
  `next` and `close`, and the file's size, rotation, duration and frame rate.
  Each platform's decoder is asked for pixels the gallery already handles:
  AVAssetReader on iOS and macOS gives BGRA, on its own serial queue, with the
  rotation from the track's preferred transform; MediaExtractor and MediaCodec
  on Android give YUV_420_888 planes, which the camera path's `yuv420ToRgba`
  converts (10-bit P010 is narrowed to 8 bits in Java), on a HandlerThread,
  with the rotation from `KEY_ROTATION`; Media Foundation's source reader on
  Windows gives RGB32 through its video processor, cropped to the display
  aperture, with the rotation from `MF_MT_VIDEO_ROTATION`; GStreamer's playbin on Linux ends in an RGBA appsink,
  with the rotation from the `image-orientation` tag. Windows and Linux reply
  on the platform thread, where a frame of the sample clip takes milliseconds.
  In browsers a hidden `<video>` element is sought to the middle of each slot
  of a frame grid, its frame duration measured during a moment of muted
  playback and rounded to a common rate; `requestVideoFrameCallback`'s
  `mediaTime` is the timestamp where it is a frame's start, the slot's start
  where it is not, and the frame goes to the task as an `ImageBitmap`; the
  browser applies the rotation itself. A file comes one frame at a time, never whole into memory, except in
  browsers, where a URL that is not already a blob is loaded into one first
  (the last point below).
- **Gallery.** A third mode, **Video file**, on the live page of every camera
  task (`lib/live/video_file_controller.dart`): the task opens in video mode,
  on the page's delegate with the camera's GPU-to-CPU fallback, and every
  frame runs with its own timestamp in whole milliseconds; a timestamp that
  repeats the one before is skipped and counted, and a result that carries
  another timestamp is reported. Play, pause and restart, where restart opens
  a new task. The view draws each frame, turned upright, with the result over
  it; the status line shows the file, the frame count, the time per frame and
  the delegate. The bundled clip (`samples/scene.mp4`, 452 KB) plays when the
  mode opens; **Choose video file** picks another. `LiveTask` gained
  `detectFrame`, the video call, for the nine tasks with a live page (Image
  Embedder compares photos and Interactive Segmenter takes taps instead).
- **Clips.** `gallery/tool/make_sample_clip.py` makes `scene.mp4` (three
  seconds at 30 fps, 960 x 540, the pose, portrait and raised-thumb photos
  drifting, H.264 main profile with a keyframe every 10 frames) and
  `rotated.mp4` (ten frames of the portrait stored on its side and tagged to
  be turned upright) from the test fixtures; `samples/README.md` records their
  sources, licence and digests.
- **Tests.** The journey test, on every platform CI runs it (macOS, iOS,
  Android, Linux, Windows, and Chromium, Firefox and WebKit), opens the video
  file mode of every live page and waits for all 90 frames with no repeated
  timestamp and no result out of step, and logs the time per frame. A second
  journey test, which logs what each decoder reported before checking it,
  decodes `scene.mp4` (90 timestamps, each within a millisecond of its
  frame's slot at 30 fps) and `rotated.mp4` (rotation 90, and Face Detector
  in video mode with that rotation finds the face in all ten frames). Unit
  tests cover the plugin's channel reader and the controller: rounding and
  repeated timestamps, pause and play, restart, the GPU fallback and a
  decoder failure.
- **Where step 8 was wrong.** Seeking a `<video>` frame by frame needs a
  seekable file, and a file served over HTTP is seekable only when the server
  answers range requests. Python's `http.server`, which the browser tests
  serve from, does not: Chromium then reports the clip seekable from 0 to 0,
  every seek shows the first frame, and the first journey run ended after one
  frame. The reader now loads a URL that is not a blob into one (a picked file
  already is), and refuses a file it still cannot seek rather than ending it
  early. Nor does `mediaTime` mean the same everywhere: Chromium and WebKit
  report the shown frame's start, and Firefox, it appears, the seek position,
  so a reader stepping from the last `mediaTime` advanced one and a half
  frames a step there and finished 60 of 90 frames in CI. A callback can also
  come too late: WebKit on a loaded CI runner missed the reader's 500 ms wait,
  and the late callback then fired with the next seek's, in the same round and
  with the earlier frame's time, which the reader took for a repeated frame
  (89 of 90). The reader now steps a fixed grid, trusts a `mediaTime` only
  when it lies clearly before the seek position, waits up to five seconds for
  a callback, and after a late one finishes the file without callbacks; with
  every callback forced to miss, WebKit runs the journey's 90 frames on every
  page. Timestamps need the file's edit list, which delays an H.264 track by
  the encoder's frame reordering (two frames in the sample clip):
  AVFoundation, MediaCodec and the browsers apply it, while GStreamer's
  buffers carry the track's media time and its segment carries the edit, so
  the Linux reader reports the stream time. Frame sizes need the display
  aperture: H.264 decodes whole 16-pixel macroblocks, and Media Foundation
  hands over all 544 rows of the 960 x 540 clip, so the Windows reader crops
  to `MF_MT_MINIMUM_DISPLAY_APERTURE` (or the track's own size). Conversion is
  mostly the decoders' own: Apple, Windows and Linux are asked for BGRA or
  RGBA, so only Android's YUV goes through the camera path's conversion, and
  browsers hand their bitmap to the task as it is. Linux needs
  `gstreamer1.0-libav` for H.264, which GStreamer's base and good plugins do
  not decode. The clip is 452 KB, not a few megabytes; ffmpeg writes a
  rotation tag only with `-display_rotation` and `-noautorotate` before the
  input.

### Native LIVE_STREAM, if profiling asks for it

The public API is the same either way, so a platform can move to native later.
The copy problem the C API poses is already solved once in this repository:
the text package compiles `native/text_stream_bridge.c` with its build hook,
Google's callback copies each result inside the callback into a struct Dart
owns and posts its address to the worker's port, and the worker reads the copy
and frees it (`packages/mediapipe-task-text/lib/src/io/native_text_stream.dart`).
A port, not a `NativeCallable.listener`: Google calls back on its own threads,
also after a hot restart has ended the worker, and a deleted listener then
aborts the VM where a closed port refuses the message. Vision would do the
same per task, copying landmarks, categories, detections and the segmenter's
masks, which are valid only during the callback. Going native,
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

Shipped, with its own note: `packages/mediapipe-task-audio/tool/AUDIO_STREAM.md`
holds the contract, the decisions, what was measured and what shipped. It
supersedes the section that stood here, which it corrects in eight places;
three of them changed the design: Google stamps the flushed tail with a
sentinel instead of a time, Google's C callback carries no user data and no
error message, and the checks and the emulation need the model's window,
rate and channels, which only the model's metadata holds.

## Order of work

1. Done: vision live stream in the package (emulated), with its tests, README
   and CHANGELOG, then the gallery and example moved onto it; one PR, verified
   by the full CI loop and a Test Lab run for the phones' drop rates.
2. Done: the gallery's video file mode over its own decoder plugin, its own
   PR.
3. Done: the audio stream mode and the gallery's microphone mode, its own PR
   (`packages/mediapipe-task-audio/tool/AUDIO_STREAM.md`).

## Decisions

- **Vision: emulated on VIDEO, on every platform.** The same frames give the
  same results in both modes on Google's runtime: all ten tasks agree to the
  last bit on macOS, Linux and Windows, 9.7 million values over five frames each
  (`live_stream_runtime_test.dart`, which prints the largest difference: 0.0 on
  all three), Face Landmarker agrees in the browsers CI runs (the API probe),
  and every live tile runs in live stream mode on the iOS simulator and Android
  (`runtime_test.dart`). Frame times match the hand-rolled VIDEO path they
  replace. In Chromium on an Apple M4 Max
  (`tool/benchmarks/2026-09-22-web-live-pipeline/run.mjs`, in git history at
  `3e217ac`, Holistic Landmarker,
  main and this change interleaved, 450 frames a block): CPU 21.6 processed
  frames a second against 21.6 on main, inference 45.6 ms against 45.8, camera
  frame to result 63.3 ms against 64.9; GPU 29.8 against 29.5, inference 29.3
  against 29.5. On the Test Lab phones (debug builds, Face Landmarker, main
  against this change in two runs the same day), live stream mode processed as
  many frames as main and dropped as many: the Pixel 8a's front camera 15.4 to
  16.3 processed frames a second with 21 to 30% dropped, against 14.0 to 17.3
  with 26 to 30% skipped; the Galaxy S24 5.6 to 6.9 with none dropped, as on
  main; the Galaxy A12 4.0 to 5.1 with 22 to 50% dropped, against 4.0 to 5.5 and
  22 to 50%. That run also showed a frame's measured inference longer than
  main's by about one conversion wherever a frame was queued (10 to 15 ms on the
  Pixel 8a, about 70 ms on the A12): the limiter started the queued deferred
  frame, which converts on the calling isolate, before the finished frame's
  result reached the listener. It now delivers the result first, which a unit
  test pins, and a second run on those two phones put inference back at main's:
  40 to 45 ms on the Pixel 8a and 101 to 133 ms on the A12, with camera to
  result on the A12 down from 270 to 300 ms to 191 to 224. A native LIVE_STREAM
  would run the same inference and change only the hop to the plugin's worker,
  so there is nothing for it to win back; revisit if a profile on a phone shows
  that hop.
- **A lazy image: `VisionImage.deferred`, live stream mode only.** Converting at
  arrival costs every camera frame its conversion, dropped ones included, and on
  Android that conversion (the gallery's YUV to RGBA in Dart) is as slow as
  inference on a slow phone. Main's numbers on the Test Lab phones, debug
  builds: the Galaxy A12 converts in 68 to 75 ms against 99 to 140 ms of
  inference at 6 to 10 camera frames a second, skipping 22 to 50% of them;
  converting every arrival would take 40 to 75% of its UI isolate there and more
  than all of it at 30 frames a second. The Pixel 8a converts in 13 to 17 ms
  against 42 to 46, the Galaxy S24 in 9 to 14 ms against 35 to 50. So a deferred
  image carries a producer, which the limiter calls when it starts the frame; a
  dropped frame is never converted, and the UI isolate converts as many frames
  as main did. The cost: the conversion runs before the frame's inference
  instead of overlapping the previous one's, as main's did too. Image and video
  mode refuse a deferred image, since they run every image and an asynchronous
  producer could reorder their timestamps. The gallery's native camera passes
  its conversion as the producer; its browser camera converts at arrival, since
  a bitmap made when the frame starts would capture a newer video frame than the
  one stamped, and `createImageBitmap(video)` costs 0.14 ms a frame in the
  benchmark above.
- **Test Lab barely shows dropping.** Its phones sit in a dark rack, and their
  cameras deliver 5 to 7 frames a second on the Galaxy S24 (main skipped none),
  14 to 24 on the Pixel 8a (main skipped about 29% of the front camera's frames)
  and 6 to 10 on the Galaxy A12 (22 to 50%). Frame and drop rates there compare
  the two paths, not a lit room at 30 frames a second.
- **The gallery decodes video with its own plugin over the platform
  decoders, not OpenCV.** OpenCV, as the face_detection_tflite example uses
  it (`dartcv4` 2.3.1 behind `opencv_dart`), measured in that example: its
  library is 10.2 to 10.6 MB on macOS and 9.1 MB on iOS, built from source by
  its build hook on every build (the example pins versions to keep the hook
  working), and every one of the gallery's CI platforms would compile it. It
  decodes in software, and the browsers would need their own path anyway.
  The owner chose not to add a dependency, so Android, Windows and Linux were
  not measured. The plugin instead uses decoders every device already has,
  with their presentation timestamps and rotation metadata, in about 1,450
  lines; its compiled Swift on macOS is 68 KB of code and data (debug build).
  The cost is four native readers to maintain where OpenCV would be one
  dependency. The plugin stays inside the gallery, unpublished, and the vision
  package still decodes nothing.
