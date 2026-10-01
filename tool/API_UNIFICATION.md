# API unification plan

**Status:** planned, not started. The goal is one public API for core, vision,
text and audio that is identical on all six platforms and follows the same
conventions in every family. Code sites that start this work carry a TODO
pointing here; `git grep -n "API_UNIFICATION.md"` lists them.

Related: [LIVE_STREAM.md](../packages/mediapipe-task-vision/tool/LIVE_STREAM.md)
plans the streaming modes on top of this API, [SHARED_CODE.md](SHARED_CODE.md)
plans sharing the code behind it, [MODEL_BUNDLING.md](MODEL_BUNDLING.md) plans
bundling models at build time, and [API_REVIEW.md](API_REVIEW.md) records
the 0.1.0 symbol review; the decisions this plan changes are listed
under [Superseded decisions](#superseded-decisions). `mediapipe_genai` is out of
scope while it is experimental; it adopts these conventions when it returns.

## Where the API stands

Measured on 2026-10-01 at `01e1897` (PR #60) with the method in the
[appendix](#appendix-measuring-the-difference).

### Across platforms

Android, iOS, macOS, Linux and Windows share one Dart implementation, so their
API is identical. Web compiles against a separate one:

- **Vision:** web task classes extend `SdkVisionTask` and inherit members the
  native classes lack:
  - `regionOfInterest` on the inherited `detectImage` and `detectForVideo`,
    and `keypoint` on `detectImage`, in 11 tasks;
  - generic `detectImage`/`detectForVideo` beside `recognizeImage`,
    `classifyImage`, `embedImage` and `segmentImage`;
  - `name` and `maxTimestamp`;
  - the browser members `detectBrowserFrame`, `attachBrowserOverlay`,
    `setBrowserOverlayOptions` and `browserOverlayActive`.

  `SegmentationOutputOptions` is exported only on web, and so is the legacy
  segmenter's `runningMode` getter.
- **Text and core:**
  - `Classifications.categories` and `ClassifierResult.classifications` are an
    `Iterable` on native and a `List` on web.
  - `textEmbeddingCosineSimilarity()` exists only on native.
  - Native exposes FFI members: `assignToStruct`, `freeStructFields`,
    `.native(Pointer)` constructors, `fromNativeArray` and `Embedding.pointer`.
  - On native, `ModelStore` takes a `Directory` and an HTTP client and its
    `get()` returns a `File`. On web it takes neither, and `get()` returns
    bytes.
- **Audio:** identical.

### Across families

These are the same on every platform:

- **Options:** text's classifier, embedder and language detector take nested
  `baseOptions`, `classifierOptions` or `embedderOptions`, and offer
  `.fromAssetPath`/`.fromAssetBuffer`, inherited from Google's original
  `mediapipe_text`. Every other task takes flat `model`, `modelPath` or
  `modelBytes` plus settings.
- **Delegates:** there are three identical enums, `VisionDelegate`,
  `TextDelegate` and `AudioDelegate`. Text and audio capability queries report
  delegates, but only EmbeddingGemma's options accept one.
- **Value types:**
  - A category is text's `Category`, vision's `VisionCategory`, `FaceCategory`
    and `ObjectCategory`, or audio's record `({index, name, score})`, which
    has no `displayName`. Text's `Category` also collides with the
    `Category` that `package:flutter/foundation.dart` exports.
  - Vision duplicates boxes, detections and landmarks per task:
    `FaceBoundingBox`/`ObjectBoundingBox`, `FaceDetection`/`ObjectDetection`
    and `FaceLandmark`/`VisionLandmark`.
  - An embedding is `Embedding` (`floatEmbedding`), `TextEmbedding`
    (`floatValues`) or `VisionEmbedding`.
- **Results:** text results have `dispose()` and `isClosed`, left over from
  results that owned native memory. Audio's result is a record typedef. Text
  says `timestampMs` where vision says `timestampMilliseconds`.
- **Methods:** vision says `detectImage`, `classifyImage` and so on, where
  Google's APIs and this repository's text and audio tasks say `detect`,
  `classify` and `embed`.
- **Cosine similarity** comes in four forms: `ImageEmbedder.cosineSimilarity`
  (static), `TextEmbedder.cosineSimilarity` (an async instance method),
  `TextEmbedding.cosineSimilarity` (static) and `textEmbeddingCosineSimilarity`
  (top-level, native only).
- **Errors:** `VisionTaskException` has `statusCode` and `gpuUnavailable`,
  `TextTaskException` only `statusCode`, and `AudioTaskException` neither.
  Core's `DownloadException` is not a `MediaPipeException`.
- **Capabilities:** every task has a `queryXxxCapabilities()`. Text also has
  `queryTextTaskCapabilities(TextTask)`, and vision exports grouped helpers
  such as `imageTaskCapabilitiesForPlatform`.
- **Public surface:** 38 public libraries across the four packages (core 10,
  vision 9, text 13, audio 6). Vision exports internal helpers:
  `ownVisionLists`, `validateLandmarkCount` and `validateVisionConfidence`.

## Principles

1. **One API everywhere.** Every public type has a single declaration that all
   six platforms compile. Platform code sits behind internal conditional
   imports; public libraries never conditionally export public types. No
   `dart:ffi`, `dart:io`, `dart:js_interop` or `package:web` type appears in a
   public signature.
2. **Availability is decided at run time, not by the API.** Everything exists
   on every platform. What Google's runtime cannot do on a platform throws
   `RuntimeUnavailableException` with its `fix`, and the capability queries
   say so in advance.
3. **One vocabulary across families.** Options, results, value types,
   delegates, errors, lifecycle and capabilities have the same shape in vision,
   text and audio.
4. **Google's names, Dart's idioms.** Task names, method verbs, option names,
   defaults and result fields follow MediaPipe Tasks, where Google's Python,
   Java, Web and iOS APIs agree. Everything Dart-specific follows Effective
   Dart: async `create`, named parameters, immutable values, unmodifiable
   `List`s and no new abbreviations. The one deliberate exception is a name
   that Flutter's core libraries already export (`Category`), because an app
   that imports Flutter could not use it.
5. **Same validation everywhere.** Options and inputs are checked in shared
   Dart before platform code runs, so the same call fails the same way on every
   platform: `ArgumentError` for bad arguments, `StateError` after `dispose()`
   or in the wrong running mode.
6. **Results are plain values.** Results are immutable Dart objects that own
   their data. Only tasks need disposing.
7. **Enforced, not remembered.** CI checks that the native and web APIs are
   identical and that the conventions hold.

## Target API

### Libraries

- Apps import one library per family,
  `package:mediapipe_<family>/mediapipe_<family>.dart`. It exports the tasks,
  options, results, models and capability queries, plus everything shared
  from core, so apps never import core directly.
- `platform_interface.dart` stays for backend registration. The registration
  files Flutter requires (`mediapipe_<family>_android.dart` and
  `mediapipe_<family>_web.dart`) stay, documented as not for apps, and core's
  `native_assets.dart` stays for build hooks.
- Everything else moves into `lib/src/`: `io.dart`, `interface.dart`, the
  `universal_*.dart` files, `vision_native.dart`, the per-task text libraries
  and the per-family `web_runtime.dart` copies.
- Internal helpers leave the exports: `ownVisionLists`, the `validate*`
  functions, the grouped capability helpers, `SdkVisionTask` and
  `BrowserVisionTask`.

### Tasks

Every task has:

- `static Future<Xxx> create(XxxOptions options)`;
- an idempotent `Future<void> dispose()`, after which any other call fails
  with `StateError`;
- a `delegate` getter, plus `runningMode` in families that have modes.

Calls run one at a time, in call order. Errors arrive through the returned
`Future`, or through the results stream in streaming modes. A `Future` cannot
cancel native work, so `dispose()` waits for work already accepted.

Methods use Google's verbs:

| Task | Image or text | Video | Streaming ([LIVE_STREAM.md](../packages/mediapipe-task-vision/tool/LIVE_STREAM.md)) |
| --- | --- | --- | --- |
| Face and Object Detector; Face, Hand, Pose and Holistic Landmarker | `detect` | `detectForVideo` | `detectAsync` |
| Gesture Recognizer | `recognize` | `recognizeForVideo` | `recognizeAsync` |
| Image Classifier | `classify` | `classifyForVideo` | `classifyAsync` |
| Image Embedder | `embed` | `embedForVideo` | `embedAsync` |
| Image Segmenter | `segment` | `segmentForVideo` | `segmentAsync` |
| Text Classifier, Text Embedder, Language Detector | `classify`, `embed`, `detect` | | |
| Audio Classifier | `classify` (clips) | | `classifyAsync` (audio stream) |

- Every vision call takes `rotationDegrees`. Only Image Classifier and Image
  Embedder take `regionOfInterest`, because they are the only tasks Google's
  runtime accepts one for.
- The stroke-based Interactive Segmenter keeps `setImage` and
  `segment(strokes)`.
- Text Proofreader and Text Summarizer keep their methods and streaming
  variants.
- Landmark connection sets keep their own classes, renamed to the names in
  Google's Python and Java APIs: `FaceLandmarksConnections`,
  `HandLandmarksConnections` and `PoseLandmarksConnections`.

### Options

- **One base.** A single abstract base in core, `TaskOptions`, replaces
  vision's `VisionModelOptions` and the FFI-era internal type of that name. It
  takes exactly one of `model` (a pinned `DownloadAsset`), `modelPath` and
  `modelBytes`, plus `delegate` (default `Delegate.cpu`). It owns their
  validation and pinned-model resolution. Every options class extends it, and
  vision and audio add `runningMode`.
- **Flat settings.** Settings sit directly on the options, with Google's names
  and defaults:
  - Classifier tasks (the image, text and audio classifiers and Object
    Detector) take `displayNamesLocale`, `maxResults` (-1 means all),
    `scoreThreshold` (0), and `categoryAllowlist` and `categoryDenylist`
    (empty by default, never both).
  - Embedders take `l2Normalize` and `quantize`.
  - Gesture Recognizer nests a `ClassifierOptions` for its canned and custom
    heads, as Google's does.
- **Text changes.** Text drops `baseOptions`, `classifierOptions`,
  `embedderOptions`, `.fromAssetPath` and `.fromAssetBuffer`. Core's FFI-era
  `BaseOptions` and `EmbedderOptions` go, and `ClassifierOptions` becomes a
  plain value used only by Gesture Recognizer.
- **`modelPath`** means what it means in Google's APIs: a file on native and a
  URL on web.
- Options are immutable and copy the collections they are given. Equatable's
  `props` and `stringify` leave the public API.

### Delegates and running modes

- One `Delegate { cpu, gpu }` in core replaces the three family enums, and
  `TaskCapabilities` drops its type parameter.
- Vision keeps `RunningMode { image, video, liveStream }`. Audio gains
  `AudioRunningMode { audioClips, audioStream }` (Google's names), with
  `audioStream` reserved the way `liveStream` is. Text has no running mode,
  as in Google's APIs.

### Inputs

- `VisionImage.fromPixels` works everywhere. `VisionImage.fromFile` follows
  `modelPath`: a file on native and a URL on web.
- New `VisionImage.fromBrowserFrame(Object frame)` takes an `ImageBitmap` or a
  video frame and replaces `detectBrowserFrame`, so every video method takes a
  `VisionImage`. It is unavailable off the web.
- `AudioData` is unchanged.

### Results and shared value types

One set of value types in core, named after Google's containers:

| Shared type | Replaces |
| --- | --- |
| `MediaPipeCategory` (`index`, `score`, `categoryName`, `displayName`) | `VisionCategory`, `FaceCategory`, `ObjectCategory`, text's `Category` and audio's `AudioClassifierCategory` record |
| `Classifications` (`categories`, `headIndex`, `headName`) | `VisionClassifications` and text's `Classifications` |
| `Embedding` (`floatEmbedding`, `quantizedEmbedding`, `headIndex`, `headName`) | `VisionEmbedding`, `TextEmbedding` and core's FFI-backed `Embedding` |
| `Detection`, `BoundingBox`, `NormalizedKeypoint` | `FaceDetection`, `ObjectDetection`, `FaceBoundingBox`, `ObjectBoundingBox` and `FaceKeypoint` |
| `NormalizedLandmark` (image space), `Landmark` (world space) | `FaceLandmark` and `VisionLandmark` |
| `Matrix` | `FaceTransformationMatrix` |
| `ConfidenceMask`, `CategoryMask` | `SegmentationMask` and vision's `CategoryMask` |

- **Category name.** `MediaPipeCategory` follows `MediaPipeException` because
  `Category` would collide with Flutter's (Principle 4). Other shared types
  carry no prefix, and family prefixes stay only on family-specific types such
  as `VisionImage`, `VisionModels` and `TextModels`.
- **Result classes.** Every task has its own result class named after the
  task, as in Google's APIs: `ImageSegmenterResult` replaces
  `SegmentationResult`, and `AudioClassifierResult` becomes a class with
  `classifications` and `timestampMilliseconds`. The stroke Interactive
  Segmenter has no result class in Google's APIs: its `segment(strokes)`
  returns a `ConfidenceMask`, and `SegmentationStroke` becomes Google's
  `Stroke`. Audit every result's field names against Google's Python, Java
  and Web results.
- **Result rules.** Results are immutable and use unmodifiable `List`s, never
  `Iterable`. They carry `timestampMilliseconds` when the task has a timeline,
  implement `toString()`, and have no `dispose()` or `isClosed`. The small
  value types implement `==` and `hashCode`.
- **Cosine similarity.** `static double cosineSimilarity(Embedding a,
  Embedding b)` sits on `ImageEmbedder` and `TextEmbedder`, as in Google's
  APIs, written in Dart so it gives the same answer everywhere. The other
  forms go.
- **EmbeddingGemma.** It folds into `TextEmbedder`, as in Google's Python and
  Java APIs: `TextEmbedder.embed(text, {TextFormatContext? formatContext})`
  with `TextModels.embeddingGemma`. `TextFormatContext` and `TextRole` stay,
  and `EmbeddingTaskType` becomes Google's `EmbeddingType`. Capability queries
  take a model so they can report that EmbeddingGemma runs only on macOS
  today.

### Errors

- `MediaPipeException` stays the base, with `RuntimeUnavailableException`
  (`fix`), `ModelDownloadException` (`failures`, `hint`) and one
  `TaskException` (`statusCode`, `gpuUnavailable`) for failures Google's
  runtime reports.
- `TaskException` replaces `VisionTaskException`, `TextTaskException` and
  `AudioTaskException`, and `DownloadException` folds into
  `ModelDownloadException`.
- `ArgumentError` and `StateError` are thrown under the same conditions on
  every platform.

### Capabilities

- Every task has `queryXxxCapabilities()` and a pure
  `xxxCapabilitiesForPlatform(TaskPlatform)` for tests.
- `queryTextTaskCapabilities`, `textTaskCapabilitiesForPlatform`, `TextTask`
  and vision's grouped helpers go.
- `TaskCapabilities` reports delegates now, and running modes once streaming
  lands.

### Models

- `VisionModels`, `TextModels` and `AudioModels` are unchanged.
- `ModelStore({String? source, http.Client? client})` is the same on every
  platform. `get()` and `find()` return a `ModelSource` (a path on native,
  bytes on web), and `prefetch()` is unchanged.
- The native-only `Directory` becomes `String? cacheDirectory`. On web it
  throws `RuntimeUnavailableException`.
- Models are bundled at build time by default, and downloading them at run
  time is opt-in through `ModelStore.allowDownloads` (done).
  [MODEL_BUNDLING.md](MODEL_BUNDLING.md) covers the pubspec lists, the
  command and the lookup order.

### Browser-only features

- Frames come in through `VisionImage.fromBrowserFrame` (see Inputs).
- Overlays drawn in the worker move off the task classes into one
  `BrowserOverlay` class in the vision library, which attaches to a task,
  takes the drawing options and detaches. It exists everywhere and is
  unavailable off the web.
- `MediaPipeWebRuntime`, which sets where browsers load Google's runtime, is
  exported from core's library and does nothing off the web.

### Streaming

[LIVE_STREAM.md](../packages/mediapipe-task-vision/tool/LIVE_STREAM.md) covers
vision, and audio's stream mode follows the same design:

- `xxxAsync(input, timestampMilliseconds: ...)` returns at once.
- Results and errors arrive on the task's `results` stream, a broadcast
  `Stream`, so nothing is buffered when no one is listening.
- Dropped frames produce nothing.

## What stays platform-specific

- **What runs.** Some combinations of task, delegate and mode don't exist in
  Google's runtime on some platforms:
  - Windows has no GPU build.
  - Google's Windows build lacks the stroke segmenter.
  - The text generation tasks run only on macOS.
  - A few of Google's GPU paths have bugs.

  [VISION_TASKS_STATUS.md](../packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
  and [coverage/matrix.json](coverage/matrix.json) list these, and the API
  reports them at run time.
- **What paths mean:** files on native, URLs on web.
- **Timestamp limits.** MediaPipe accepts larger timestamps on native than in
  browsers. Every platform validates against the browser limit, about 285
  years of milliseconds, so the same input is valid everywhere.
- **Speed and memory**, which depend on each runtime.

## Delivery

Start after PR #60 lands, since its shared `VisionTaskRunner` is the base for
vision. Each phase lands with CI green and behavior unchanged (the reference
tests keep passing), and shrinks the API-difference baseline from phase 0.

0. **Guardrails.**
   - Add the native-vs-web API comparison to CI (appendix), with today's
     differences checked in as a baseline that may only shrink.
   - Add a conventions check: no platform types in public signatures; every
     task has `create`, `dispose`, `delegate` and a capability query; every
     options class extends `TaskOptions`; no public name collides with
     Flutter's or Dart's core libraries.
   - Snapshot the public API with `dart_apitool`, so every API change shows up
     in review.
1. **Retire first.** Delete `InteractiveSegmenterLegacy` (its TODOs and grep
   already exist), so nothing is unified only to be deleted.
2. **Core.** Add `Delegate`, `TaskOptions`, `TaskException`, the shared value
   types, `ModelStore` with `ModelSource` and the non-generic
   `TaskCapabilities`, and move the FFI-era public types into `src/`.
3. **Vision.**
   - One class per task on every platform, with the platform chosen inside
     `VisionTaskRunner`, which gains a web backend.
   - Google's verbs, shared value types, `regionOfInterest` only where Google
     accepts it, `VisionImage.fromBrowserFrame`, `BrowserOverlay`, Google's
     connection class names, and one export list.
4. **Text.** Flat options with `delegate`, shared value types, plain results,
   static `cosineSimilarity`, EmbeddingGemma folded into `TextEmbedder`, the
   proofreader and summarizer on the same base types, and per-task capability
   queries.
5. **Audio.** An `AudioClassifierResult` class on the shared types, `delegate`
   and `AudioRunningMode`.
6. **Surface and docs.**
   - One app-facing library per family, with the legacy entry points moved
     into `src/`.
   - Update the READMEs, MIGRATION.md (a full old-to-new symbol table), the
     CHANGELOGs, CONTRIBUTING's "How to add a task", API_REVIEW.md, the
     gallery and the examples.
   - Release as 0.2.0. The baseline is now empty: the native and web APIs are
     identical.
7. **Streaming.** Build LIVE_STREAM and audio stream mode on the unified API.

## Enforcement

- **CI** checks API parity (must be identical), the conventions and the public
  API snapshot, alongside the existing reference tests and coverage gate.
- **Samples:** README and dartdoc samples are analyzed for both native and
  web.
- **Lints:** keep `lints/recommended` and `public_member_api_docs`, and add
  `comment_references` and `unawaited_futures`.
- **Class modifiers:** public classes are `final` unless they are meant to be
  extended (`MediaPipeException`, `TaskOptions`), and value types are
  `@immutable`.

## Compatibility

Nothing is published yet, so this ships as breaking changes in one minor
release (0.1.0 to 0.2.0). There are no deprecated aliases; MIGRATION.md maps
every old symbol to its replacement.

After the first pub.dev release, semantic versioning applies:
- a symbol is deprecated with `@Deprecated` naming its replacement for at
  least one minor release before it is removed;
- the `dart_apitool` snapshot catches accidental breaking changes.

## Superseded decisions

These [API_REVIEW.md](API_REVIEW.md) decisions change:

- One failure type per family (`VisionTaskException`, `TextTaskException`,
  `AudioTaskException`) becomes one `TaskException`.
- Keeping `BaseOptions`, `ClassifierOptions` and `EmbedderOptions` for classic
  text tasks gives way to flat options on `TaskOptions`.
- `TaskCapabilities` with a per-family delegate type becomes one `Delegate`
  and a non-generic `TaskCapabilities`.
- The `AudioClassifierCategory` and `AudioClassifierResult` records become
  classes on the shared types.
- `BrowserVisionTask` on the primary import gives way to
  `VisionImage.fromBrowserFrame` and `BrowserOverlay`.
- `queryTextTaskCapabilities`, `textTaskCapabilitiesForPlatform` and `TextTask`
  are removed.

## Decisions to confirm

1. **Google's verbs:** `detect` instead of `detectImage`, and so on.
   Recommended, since it matches Google's four APIs and this repository's own
   text and audio tasks.
2. **Fold EmbeddingGemma into `TextEmbedder`.** Recommended, as Google does.
3. **Streaming results:** a broadcast `Stream` on the task, or Google's
   listener in the options. A `Stream` is recommended as the Dart idiom.
4. **Browser overlays:** a `BrowserOverlay` class available everywhere, or a
   web-only import. The class is recommended because it keeps one import.
5. **Names:**
   - `MediaPipeCategory` for the shared category, or `ClassificationCategory`;
   - `Delegate`, or `TaskDelegate` if the generic name collides in apps;
   - `TaskOptions` and `TaskException`.
6. **`VisionImage.fromEncoded(bytes)`** for JPEG or PNG bytes on every
   platform. Google's C API only loads files, so native would decode through
   a temporary file. Recommended later, not in this plan.

## Appendix: measuring the difference

Run the Dart analyzer over each family's main library twice, declaring the
libraries each compiler provides:

- native: `dart.library.io`, `dart.library.ffi` and `dart.library.isolate`;
- web: `dart.library.js_interop`, `dart.library.js_util`, `dart.library.html`
  and `dart.library.js`.

Without declared variables, the analyzer always takes the default branch of an
`if (dart.library.…)` export. Create
`AnalysisContextCollectionImpl(includedPaths: [...], declaredVariables: {...})`.
Then, for each name in the library's `exportNamespace.definedNames2`, write
out its declaration. For classes, also write out their constructors, static
members and `interfaceMembers`, as display strings. Diff the two lists. Phase
0 turns this into a script under `tool/`, with the baseline file beside it.
