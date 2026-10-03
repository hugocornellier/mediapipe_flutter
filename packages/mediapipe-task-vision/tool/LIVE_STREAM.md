# Live stream mode (planned)

**Status:** planned, not started. Camera frames run in VIDEO mode today, and
`RunningMode.liveStream` throws `UnsupportedError` when a task is created. The
goal is to split LIVE_STREAM from VIDEO properly, as Google's runtimes do. Each
code site to revisit carries a TODO, starting with the one on
`RunningMode.liveStream`; `git grep -n "TODO.*LIVE_STREAM"` lists them.

## Google's three modes

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
- VIDEO calls `TaskRunner::Process`, which waits for the graph to go idle.
  LIVE_STREAM calls `TaskRunner::Send`, which returns immediately
  ([task_runner.cc](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/cc/core/task_runner.cc#L241)).
  Both reject timestamps that do not increase.
- The web tasks have no LIVE_STREAM: `RunningMode = 'IMAGE'|'VIDEO'`
  ([vision_task_options.d.ts](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/web/vision/core/vision_task_options.d.ts#L24)).

## This repository today

- The VIDEO methods (`detectForVideo`, `recognizeForVideo`, ...) serve both
  decoded video and cameras.
- The package never drops a frame. `VisionTaskWorker`, the Android plugin's
  executor and the web worker run every request in order, so a caller that
  submits each camera frame without awaiting falls further and further behind.
- The gallery rebuilds Google's policy by hand (one in flight, the newest one
  pending) in `gallery/lib/live/live_camera_controller_native.dart` and
  `gallery/lib/web/live_camera_controller.dart`. The vision example skips every
  frame that arrives while it is busy, which is a queue of 0.
- The native gallery controller stamps a pending frame when it starts, not when
  it arrived. Google's API takes the timestamp at submission.
- The gallery has one live page with two input modes, camera and still image.
  Nothing in the repository decodes a video file: the README documents VIDEO
  for "decoded video", but no demo feeds one, so the gallery shows what
  LIVE_STREAM is for and nothing that shows what VIDEO is for.

## Plan

1. Implement `RunningMode.liveStream` with Google's method names:
   `detectAsync`, `recognizeAsync`, `classifyAsync`, `embedAsync` and
   `segmentAsync`. Each takes an image and a millisecond timestamp and returns
   at once. Results and errors arrive on the task's `results` stream, tagged
   with their frame's timestamp, as
   [API_UNIFICATION.md](../../../tool/API_UNIFICATION.md) plans for every
   streaming mode. A dropped frame produces nothing.
2. Apply Google's policy (one in flight, one queued, newest wins) in the
   package, checking timestamps at submission. Drop frames on the caller's
   isolate, before their pixels are copied to a worker. `VisionTaskRunner`
   (native platforms) and `SdkVisionTask` (Android adapter and web) are the
   shared entry points, so one limiter can serve both.
3. Keep frames cheap to drop. The gallery converts a camera frame (on the web,
   takes its bitmap) only when the frame starts, so a dropped frame costs
   nothing. An API that takes a finished `VisionImage` converts every frame
   before the limiter sees it: measure that, or accept frames that convert
   lazily.
4. Leave VIDEO unchanged for decoded video, where every frame matters.
5. Move the gallery and the vision example to live stream mode, delete their
   frame dropping, and update the README's "Video and live cameras" section.
6. Test frames dropped under load, the newest queued frame winning, no result
   for a dropped frame, timestamps checked at submission, errors reaching the
   listener, and disposal with a frame queued.
7. Give the gallery a video file mode, so the two modes are shown side by
   side: the camera on LIVE_STREAM, a file on VIDEO. The face_detection_tflite
   example is the model: its home screen offers Live Camera, Still Image and
   Video File, and the Video File screen decodes every frame, runs detection
   on each, draws the result and writes the annotated clip, which it then
   plays back. For the gallery:
   - A third input mode on the live page beside camera and still image, for
     every camera-capable vision task. The file's frames go through
     `detectForVideo` with the file's own timestamps (frame index over the
     frame rate), every frame processed, results drawn per frame, and the
     processed clip shown as it is produced, with frame count and time per
     frame on the status line.
   - A frame source per platform, which is the work. That example reads with
     OpenCV's `VideoCapture` (the `dartcv`/`opencv_dart` package) on
     Android, iOS and the desktops and writes with its `VideoWriter`; that
     adds a large native dependency to the gallery, so weigh it against a
     small decoding plugin over the platform decoders (AVAssetReader on Apple
     platforms, MediaCodec on Android, Media Foundation on Windows, GStreamer
     or ffmpeg on Linux). In browsers a `<video>` element plays the file and
     `requestVideoFrameCallback` hands over every frame, as the web camera
     controller already does for a stream; with playback paused and stepped
     by `seek`, no frame is skipped.
   - A bundled sample clip of a few seconds (a face, hands and a body in one
     short scene, a few megabytes) beside the sample images, listed in the
     manifest like them, so every platform's journey test can open the mode,
     process the whole clip and check that every frame produced a result and
     that the timestamps increased strictly.
   - The README's "Video and live cameras" section becomes two: video files
     on VIDEO with `detectForVideo`, cameras on LIVE_STREAM with `detectAsync`,
     each pointing at the gallery mode that demonstrates it.

## Open decision: emulate on VIDEO, or call native LIVE_STREAM

Recommended: run Google's VIDEO graph and apply the policy in Dart. Every frame
that gets processed has the same result as under native LIVE_STREAM, since both
modes turn on the same tracking and smoothing and only the limiter's location
differs. One implementation covers all six platforms, including the web, which
has no LIVE_STREAM.

Going native, platform by platform:

- **Desktop:** Google's C library exports `MpFaceLandmarkerDetectAsync` and the
  other `*Async` calls, but the result callback runs on a MediaPipe thread and
  its arguments are valid only during the call
  ([face_landmarker.h](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h#L92)).
  `NativeCallable.listener` does not make the caller wait, so the arguments are
  gone before Dart reads them; `NativeCallable.isolateLocal` aborts when called
  from another thread; `NativeCallable.isolateGroupBound` is experimental in
  Dart 3.13. Google's Python wrapper uses the same C API and copies each result
  inside its ctypes callback
  ([async_result_dispatcher.py](https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/mediapipe/tasks/python/core/async_result_dispatcher.py#L146)).
  Dart would need a small C shim for that copy, and the desktop build hooks
  compile no C today. `nativeRunningMode`, plus the running-mode mappings in
  `native_face_detector.dart`, `native_face_landmarker.dart` and
  `native_object_detector.dart`, would map the new mode.
- **iOS:** `packages/mediapipe-core/native/ios/vision_sdk_bridge.mm` already
  copies results into C structs, but its `Configure` rejects LIVE_STREAM. It
  would adopt the SDK's live stream delegates and post copied results to Dart.
- **Android:** `MediaPipeVisionPlugin.java` maps only IMAGE and VIDEO.
  `detectAsync` with a result listener, sending results over an event channel,
  would work.
- **Web:** there is no LIVE_STREAM to call.

The public API is the same either way, so a platform can move to native later
if profiling shows a gain.
