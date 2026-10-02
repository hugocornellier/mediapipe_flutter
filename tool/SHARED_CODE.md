# Shared implementation plan

**Status:** all three items shipped: 1 and 2 with the API unification
(0.2.0), item 3 for the browser with it and for Android after it. "Where
the code stands" records the starting point.

- **Item 1:** `VisionTaskChecks` runs the same mode, rotation, timestamp and
  disposal checks for every vision task on every platform, with the browser
  timestamp limit everywhere; core's `checkClassifierSettings` and
  `requireDelegate` give vision, text and audio the same option checks and
  delegate refusal.
- **Item 2:** one decoder per family. Vision's Android adapter reshapes the
  Java plugin's compact lists into Google's JavaScript result shape
  (`VisionResultData`), keeping packed landmarks and masks, and
  `lib/src/results/decoders.dart` reads both it and the browser worker's
  replies; Android boxes now reach the decoder as whole pixels. Text and
  audio decode their JSON in one place too. The Android frame-time
  comparison on the Test Lab phones and the Android GPU run are still to do
  before release.
- **Item 3:** the text and audio `bridge.js` files matched in all but two
  lines, and their Dart loaders and create/run/close plumbing were the same,
  so core now ships one `assets/task_bridge.js` and
  `package:mediapipe_core/web_task_bridge.dart` (`WebTaskWorker`), which
  both web plugins use with their own `worker.js`. The workers stay per
  family: they share only a 15-line message loop, and the rest is each
  family's tasks. Vision keeps its own bridge for frames, masks and
  overlays. On Android, core is now a library the three Java plugins build
  on: `TaskHost` owns the worker thread, the task and model-buffer maps,
  the channel's dispatch and replies, and the `update` events of a streamed
  request, and `TaskJson` shapes Google's shared classification and
  embedding containers as its JavaScript API does. Each family keeps only
  what Google's SDK needs from it: how each task is created, run and
  closed, and vision's GPU probe and masks channel. The wire formats did
  not change, so the Dart adapters and their tests are as they were.

## Where the code stands

Measured on 2026-10-01 across core, vision, text and audio, excluding Google's
copied C headers (32,741 lines):

| Code | Share |
| --- | --- |
| Runs on all six platforms: API, types, options, validation, capabilities | 27% |
| Shared by iOS and the three desktops: the FFI path to Google's C API | 40% |
| Build hooks that fetch and verify the runtimes | 7% |
| One platform only: web 3,456 lines, iOS 2,600, Android 2,177 | 25% |

The all-six share includes a 2,700-line table of face mesh connections; without
it, the share is about 21%.

## Plan

Smallest risk first, after PR #60, alongside API_UNIFICATION.md's phases.

1. **One set of input checks.** `SdkVisionTask._check` (Android and web) and
   `VisionTaskWorker._check` with `processVideo` (iOS and desktop) check the
   running mode, rotation, timestamps and disposal separately, and disagree:
   - After `dispose()`: "<Task> has been disposed." against "Vision task has
     been disposed."
   - Timestamps: "Must strictly increase and fit MediaPipe timestamps", with a
     limit of 9007199254740 ms in browsers and 2^63 / 1000 on Android, against
     "Must be nonnegative, strictly increasing and fit MediaPipe timestamps",
     with 2^63 / 1000.

   Move them into one function that both call. This delivers principle 5 of
   API_UNIFICATION.md, "Same validation everywhere", and its single browser
   timestamp limit, so land it with that plan's vision phase.
2. **One vision result decoder for Android and web.** Text and audio already
   work this way: their Java plugins send results in the JSON shape of Google's
   JavaScript API, and one Dart decoder serves every platform. Vision still
   decodes twice. The static decoders in `mediapipe_vision_android.dart` read a
   compact positional format of packed arrays, and `lib/web_src/result.dart`
   reads the web worker's named fields. Agree on one wire format for both, keep
   one decoder, and delete the other. Keep packed typed arrays for landmarks
   and masks if that is why the compact format exists, and compare frame times
   on Android with the gallery's Stats chart before and after.
3. **Text and audio adapters in core.**
   - Their `bridge.js` files match in 77 of 79 non-blank lines and their
     `worker.js` files in 26. One bridge and one worker in core, configured
     per family, would serve both.
   - Their Java plugins match in 98 lines: the worker thread, the model
     buffers and the channel handling. Sharing Java between Flutter plugins
     needs an Android library in core, so weigh that cost against the
     duplication before doing it.

## What stays per runtime

Each of Google's runtimes needs its own adapter: the FFI classes over Google's
C API (the desktops, and iOS through the Objective-C++ bridge), the Java plugin
over Google's Android SDK, and the web worker over Google's JavaScript SDK.
Removing one would mean building that platform's runtime from source instead of
using Google's official binary, which this repository does not do.

## Verification

- `dart_apitool` reports no public API change. Item 1 changes error messages,
  so record the new wording in the CHANGELOGs.
- All 22 required checks pass. Item 2 also needs an Android GPU run on the
  Test Lab phones, and item 3 the web suites in Chromium, Firefox and WebKit.
- Expect roughly 500 fewer lines. The real gain is one place per behavior.
