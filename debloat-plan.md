# Debloat plan before the 0.1.0 pub.dev release

Checked at `ebe8ffd` (`main`, October 12, 2026), which `main` now carries as
`a9cbed4` (#84 and #85 squashed). Of the files cited here only
`gallery/tool/browser/test_browser.mjs` differs between the two, and its
references are at `a9cbed4`; every other line number is the same at both.
Steps 1 to 3 of the [suggested order](#suggested-order)
([The guards](#the-guards-step-1), the API trims and the FFI kit), B1 and B2
are done on `chore/oct12-combined`, with Google's 1.1.1 libraries; their
changes are not yet reflected in the line numbers below. The first pass (#77) is done; it is summarized under
[The first pass](#the-first-pass-77), and its full record is this file at
`a9cbed4` (`git show a9cbed4:debloat-plan.md`).

**Decision (October 12): everything here lands before 0.1.0**, in the two
weeks before publishing. Nothing has been published, so removing or reshaping
API now costs nothing, while the same change after 0.1.0 breaks callers. The
B, S and R groups below say what each item touches, not when it lands; the
[suggested order](#suggested-order) sequences all of them. [Keep](#keep)
lists what stays, including the consolidations judged not worth doing.

## Where things stand

| | `a7eed82` (end of #77) | `f52b6cb` (October 9) | `ebe8ffd` (now) |
|---|---|---|---|
| Tracked files | 786 | 873 | 874 |
| Lines in tracked text files | 283,902 | 309,245 | 310,402 |
| Dart lines in the packages' `lib/` | 20,629 | 24,628 | 24,635 |
| Archives: core, vision, text, audio | 44, 304, 32, 31 KB | 46, 305, 31, 31 KB | 46, 305, 31, 31 KB |
| Archives: decision, retrieval | | 19, 23 KB | 19, 23 KB |

- **Growth since #77 is features.** Decision and Retrieval (#79, #81, #82)
  are 69 files and 17,603 lines, and one Retrieval fixture is 10,468 of them
  (R8). Since `f52b6cb` only #83 (phone re-pins) and #84 (CI, and this file)
  have landed; this file is most of their 1,157 lines.
- **Line counts mostly measure fixture layout.** JSON is 171,907 of the
  310,402 lines (55%), nearly all test fixtures written one number per line.
  Files, archive bytes and `lib/` Dart lines say more about the code.
- **What pub.dev receives:** all six packages pass `flutter pub publish
  --dry-run` with zero warnings and together send 455 KB (`publish_check.py`
  with Decision and Retrieval added on a scratch copy; see B4).
- **Dead code is almost gone.** A resolved-AST scan of all 5,180 declarations
  finds nothing unused in hand-written code beyond the leftovers in S2 and R9
  and what [Keep](#keep) explains.
- **What is left is duplication.** The families repeat their plumbing: a
  worker isolate six times, a serial request queue six times, a close-once
  native handle seventeen times, and the filling and copying of core's own C
  structs. Shared helpers in core remove about 1,100 shipped lines; repository
  helpers remove about 1,000 more (estimates, conservative where sizings
  differ). Data layout accounts for another 17,900 lines (S3, R8). Lists and
  docs still miss the new families, and public API that 0.1.0 would freeze
  still has redundant names.

### Since the October 9 status

- **The phone pins are decided (#83).** Vision, text and audio on Android and
  iOS now pin Google's October 8 rebuilds, which add Google's Clearcut
  usage-logging uploader (`play.googleapis.com/log`).
  `packages/mediapipe-core/tool/PER_FAMILY_RUNTIMES.md:190-202` records this;
  `doc/privacy_and_licenses.md` does not yet (B1).
- **The ruleset is fixed.** `main`'s "PRs with green CI" ruleset was edited on
  October 11. All 16 checks it requires exist and reported on #84, so merges no
  longer need the admin bypass. It requires no Decision, Retrieval or Bundled
  models job (B6).
- **Test Lab ran on #83's branch** (`chore/oct8-phone-runtimes`, run
  37939566313, October 9). The Pixel 8a and Galaxy S24 passed; the Galaxy A12
  failed 4 of 38, the same count as its camera failures on October 8 (the four
  were not re-opened).
- **#84** serves Google's pinned web runtimes locally for the browser
  comparisons and raises two timeouts. It changes no item here.
- **The two October 8 audits are folded in.** They were written at `5228749`
  (8 items) and `3cf49f3` (23 items) and never committed. All 31 items were
  re-checked at `ebe8ffd`; all are still open, and several grew with
  Retrieval. [Earlier IDs](#earlier-ids) maps their numbers.
- **October 12, a full duplication pass:** clone scans over every source file,
  function-level hashing of every Dart, Python and JS function, and a review of
  every cluster (see [How this was checked](#how-this-was-checked)). It
  extended S1 and R1 to R9 with measured designs, corrected several counts,
  and added S4, S5 and R10 to R15, the release gaps in B1, B3, B4 and B5, and
  the [Keep](#keep) entries for the consolidations not worth doing.

### The guards (step 1)

On `chore/debloat-guards`, off `a9cbed4`, October 12. Not yet pushed.

- **Snapshots of all 26 public libraries** (B4, R14): `tool/api_parity` finds
  the packages from `packages/*/pubspec.yaml` and writes one snapshot per
  `lib/*.dart` under `snapshots/<family>/`. A family's app-facing snapshot
  starts with `include package:mediapipe_core/mediapipe_core.dart` and lists
  only its own declarations; the check fails if the family stops re-exporting
  any of core's unchanged. Core plus each delta rebuilds the four old full
  snapshots line for line, and 1,729 snapshot lines for 5 libraries became
  1,429 for 26. Decision's app-facing library, never checked before, adds no
  finding. B3's names now show in a snapshot: the wheel exports in
  `core/native_assets.txt`, the 31 model constants in `*/models.txt`, and the
  internal runtime constants in the Decision and Retrieval snapshots. One
  analysis context per package and platform keeps the check at 20 s.
- **One family inventory** (B4, R10): `packages/mediapipe-core/tool/families.py`
  finds `packages/mediapipe-task-*`. `publish_check.py`, `model_pins.py`,
  `check_docs.py`, `gallery/tool/test_desktop.py` and the Makefile
  (`TASK_FAMILIES`) read it. `model_pins.py` parses both registry formats in
  every family, so the mirror and `model_sha256` see Decision's and
  Retrieval's 8 pins. `packageOf` derives the folder and refuses core; the
  gallery builder takes its family list from its model table and tests that
  it covers every family; core's `web_runtime_host_test.dart` parses every
  `runtime.json`.
- **`make test` and `make models` for six packages** (B4, R6): `test_only`
  runs `test_core` and every `test_<family>`. `models` downloads every
  family's models but Decision's and Retrieval's (678 MB and 388 MB), which
  `make models_all` adds; their reference tests skip without them, and
  CONTRIBUTING says so.
- **Decision's Windows library in the inventory** (B4):
  `runtime_inventory.dart` prints `wheelRuntimes` too, so
  `consumer_packages.family_runtime` returns it and `mirror_runtime_assets.py`
  mirrors the wheel by its digest.
- **The bundled-models test for all five families** (B4): Decision and
  Retrieval list the same EmbeddingGemma 2 (text and vision), which the app
  bundles once; Decision routes a question and Retrieval ranks a neighbour
  with it. It passed on macOS arm64 in debug and release. Linux and Windows
  run it in `bundled-models.yaml`, the first CI run of Decision with this
  model off macOS.
- **`tool/check_repository.py`** (B4, R10, R19), run in `builder.yaml`. It
  checks the lists that stay hand-written: the README support table (now with
  Decision and Retrieval rows), CONTRIBUTING's first release (now six
  packages), core's `bundlableFamilies` and `bin/web_runtime.dart`, each
  family's Makefile targets and coverage-matrix test, one family per matrix
  task, and the bundled-models subset. It also checks the pins that move
  together: package versions and SDK and Flutter constraints, each family's
  browser runtime version against its `runtime.json`, the Flutter version in
  the docs against every workflow's, and models two families pin (one file
  has one URL and SHA-256; one name has one pin). That last check covers the
  shared EmbeddingGemma 2 pin. `check_web_deployment.py` reads vision's
  `runtime.json` instead of hardcoding `1.0.1`.
- **Coverage-matrix tests for every family** (R5):
  `packages/mediapipe-core/test/support/coverage_matrix.dart` holds the
  check. Text and vision use it; audio, Decision and Retrieval gain theirs,
  the WebGPU families with a hardware adapter and a registered backend. All
  five agree with the matrix.

**Decided October 12:** the shared EmbeddingGemma 2 pin stays two copies with
the check above (a core constant would be one more frozen name); `make test`
leaves the large models to `make models_all`; the vcam manual modes and the
CocoaPods spec stay (R6), each to be labeled as unused by CI.

## Before publishing

In this order. These block 0.1.0, or 0.1.0 would freeze them.

### B1. Describe the phone telemetry, by the binary each platform bundles

**Done on `chore/oct12-combined`:** the privacy doc's usage-logging table
follows the binaries the packages bundle since the 1.1.1 libraries (every one
has the uploader, Decision's too), quotes Google's privacy notice, and lists
PyPI and Hugging Face among the hosts. As found:

`doc/privacy_and_licenses.md:27-34` says Google's usage-logging client "was
observed" with Google's Windows library. Since #83 it is also in the vision,
text and audio libraries on Android and iOS, and Retrieval's libraries carry it
everywhere. On iOS it uploads: on the Simulator, one POST per task close with
the app's bundle ID in the User-Agent, and a close waits about 4 s when the
packets drop. On Android the libraries contain the uploader, but under FFI it
logs "Failed to get JNIEnv in AndroidNetworkManager::OnAttachedToJvm()" and,
as far as Test Lab's logs and the binary show, sends nothing; no network
capture has confirmed it, so say "contains an uploader" there. The decision libraries have none
(`packages/mediapipe-core/tool/PER_FAMILY_RUNTIMES.md:194-199`), but Decision
on Windows does not use a decision library: it bundles the 1.1.0 wheel's
library (`family_runtimes.dart:296-311`), and Decision's own Windows CI blocks
the logging host (`decision.yaml:46-53`). Write the table by the binary each
family bundles on each platform; say when it uploads (a task's close) and how
to block it, and keep "observed to upload" apart from "contains an uploader".

The same doc's host tables are behind: `:14` lists only GitHub for build-time
downloads, though Decision's Windows library comes from
`files.pythonhosted.org`, and `:20` lists only `storage.googleapis.com` for
models, though the EmbeddingGemma 2 models come from Hugging Face
(`packages/mediapipe-task-decision/lib/models.dart:51-73`,
`packages/mediapipe-task-retrieval/lib/models.dart:13-20`).

### B2. Notices

**Done on `chore/oct12-combined`, but for the OpenCV question:** Google's 1.1.1
build ships the same `LICENSE` and `NOTICE` with every family, so core carries
them once (`packages/mediapipe-core/third_party/`) and vision dropped its 1.0.0
copies; vision keeps `OPENCV_CAROTENE_NOTICES` until Google says whether its
libraries need it. As found:

Only vision ships Google's notices (`packages/mediapipe-task-vision/third_party/`:
`LICENSE`, `NOTICE`, `OPENCV_CAROTENE_NOTICES`). Text, audio, Decision and
Retrieval also bundle Google's libraries and ship none. Two docs disagree:
`doc/privacy_and_licenses.md:40-42` says the downloaded archives carry
Google's `LICENSE` and `NOTICE`, and `PER_FAMILY_RUNTIMES.md:155` says
Google's delivery has neither. Settle with the Google contact whether core
should carry one `NOTICE` for every family and whether the OpenCV notice still
applies to the per-family libraries, then correct whichever doc is wrong.

`mirror_runtime_assets.py` now lists Decision's and Retrieval's models and
Decision's Windows wheel (the guards), and labels every model but the three
Gemma text models Apache-2.0. Confirm the licenses of Laya, GLiNER2.5-Decide
and EmbeddingGemma 2 (Decision's registry calls EmbeddingGemma 2 Apache 2.0)
and set any other there.

### B3. Public API that 0.1.0 freezes

Removing any of this after 0.1.0 is a breaking change.

- **Internal constants.** `mediapipe_decision.dart:15-21` exports
  `decisionRuntimeVersion`, `embeddingGemma2TextTargets` and
  `webGpuAdapterPrefix`; `mediapipe_retrieval.dart:20-26` exports
  `retrievalRuntimeTargets`, `retrievalRuntimeVersion` and
  `webGpuAdapterPrefix`. Only the packages and their tests use them, the web
  plugins reach the prefix through `platform_interface.dart`, and no older
  family exports anything like them. Drop them from the public libraries; S1
  step 3 makes the prefix core-private. **Done on `chore/oct12-combined`:**
  the runtime versions became private per-platform functions, the targets
  tests need come from `src/`, and S1 step 3 moved the prefix into core.
- **Redundant model constants.** **Done on `chore/oct12-combined`:** every
  family pins each model once, inline in `XModels`; the tests read
  `XModels.x.sha256`, and `model_pins.py` and both vision tools read the one
  format. As found: Vision's `lib/models.dart:1-189` declares 22
  top-level constants beside `VisionModels` (an `xUrl` and an `xSha256` per
  model, such as `blazeFaceShortRangeUrl` and `faceLandmarkerSha256`), text's
  `lib/models.dart:1-80` six `xModel` constants that `TextModels` aliases, and
  audio's `lib/models.dart:1-23` `yamnetUrl`, `yamnetSha256` and `yamnetModel`.
  `models.dart` is a public library in every family (core's bundler imports
  `package:<family>/models.dart`, `model_bundler.dart:250`), so all 31 names
  ship; since the guards, the snapshots show them. Decision and Retrieval
  already declare each pin once, inline in `XModels`; do the same everywhere.
  This also leaves one format for `packages/mediapipe-core/tool/model_pins.py`
  to parse (it has a path per format) and lets vision's `tool/test_desktop.py:77-96`
  drop its own regexes. Tests that read the constants move to
  `XModels.x.sha256` (`audio_classifier_test.dart:70`,
  `audio_stream_runtime_test.dart:85`, `face_detector_test.dart:64` and
  `:247`, `face_landmarker_test.dart:75`, `object_detector_test.dart:110`).
  About 96 lines.
- **Core's wheel extraction.** **Done on `chore/oct12-combined`,** as
  recommended below: `bundleFamilyRuntime` falls back to the wheel itself,
  the wheel's class, table and helper are no longer exported, Decision's hook
  is Retrieval's three lines, and the tests and tools import the table from
  `src/`. A target with neither library now fails Decision's build as it
  fails every other family's. As found: `native_assets.dart:5` exports all of
  `family_runtimes.dart`, including `WheelRuntime` (`:270`), `wheelRuntimes`
  (`:296`) and `bundleWheelRuntime` (`:409`): about 110 lines for one target,
  Decision on Windows, which extracts Google's 61 MB library from the 1.1.0
  Windows wheel until Google builds a per-family one. Their TODO says to
  retire them then. **Recommended:** fold the fallback into
  `bundleFamilyRuntime` (when `familyRuntimes[family]` lacks the target, use
  `wheelRuntimes[family]`) and export `family_runtimes.dart` with `hide
  WheelRuntime, wheelRuntimes, bundleWheelRuntime`. Decision's hook
  (`hook/build.dart:12-16`) then becomes Retrieval's three lines, nothing new
  is published, and retiring the wheel later changes no API. Core's
  `family_runtimes_test.dart:67` and `:90` can import `src/`; Decision's
  `runtime_targets_test.dart:17` and `:30` need literals or one wheel-agnostic
  export such as `familyRuntimeTargets(String family)`. The other options:
  move them to a separate core library only Decision's hook imports (still
  public), withdraw Decision on Windows (a product decision), or publish them
  as they are and break later.
- **Vision results repeat their metadata.** **Done on
  `chore/oct12-combined`:** `VisionResult`, with the EXIF wording. As found:
  All ten result classes in
  `vision/lib/src/types/results.dart` (`:15`, `:45`, `:76`, `:118`, `:158`,
  `:207`, `:249`, `:322`, `:352`, `:382`) declare `imageWidth`, `imageHeight`
  and `timestampMilliseconds`. One exported `abstract base class
  VisionResult` with `super.` parameters saves about 76 shipped lines and gives
  the gallery's overlay one type to read. The classes are `final`, so a
  supertype could also be added after 0.1.0 without breaking callers; per the
  decision above it lands now. The width and height docs differ slightly
  (some mention EXIF correction); keep the more precise wording.
- **Untested public API.** **Native half done on `chore/oct12-combined`:**
  Google's Python answers for image and audio records and audio embeddings
  (the audio on the full model), and native tests against them, which found
  that Google's runtime refuses media without a path (the package now passes
  the record's id) and that its audio embeddings vary (UP-058). Browser cases
  are still to add. As found: `SemanticRetriever.insertImage` and `insertAudio`
  (`retrieval_tasks.dart:214`, `:232`) are in the package README and wired in
  both the native runner and the web worker, but nothing in the repository
  calls them. `UniversalEmbedder.embedAudio` (`:108`) is tested only for
  rejecting empty input (`retrieval_unit_test.dart:187`); no test embeds
  audio, and `tool/generate_reference.py` has no audio case. Add native
  reference and browser cases, or hold the three calls back from 0.1.0.

### B4. Publishing tooling, lists and pins for six packages

[The guards](#the-guards-step-1) did most of this: the snapshots, one family
inventory, six packages in `publish_check.py`, `make test` and `make models`,
the runtime inventory, the bundled-models test, and the list and pin checks.
What remains:

- Decision and Retrieval have no `example/example.dart`; the other four do,
  and pub.dev's score checks for one.
- `doc/platform_setup.md:118` and
  `packages/mediapipe-core/tool/MODEL_BUNDLING.md` name neither family's
  `models` setting or `byName` map.
- `model_pins.py` parses two registry formats until B3 leaves one (done).

### B5. Devices

- Test Lab's task list (`android-face-testlab.yml:100-102`) has no Decision or
  Retrieval task, so neither has run on a physical phone; their CI uses the
  x86_64 emulator and the iOS Simulator. Adding the tasks is not enough: the
  app Test Lab builds, `gallery/integration_test/sdk_all_test.dart`, imports
  neither `decision_maker_test.dart` nor `retrieval_test.dart`, and both
  download their models on demand. (R2 made the suite import both; they run
  once the build bundles the tasks, and skip until then.)
- The Galaxy A12 failed 4 of 38 on October 8 and October 9. On October 8 all
  four were CameraX's "The camera device has encountered a recoverable error".
  On the 1.1.1 build it passed all 38 on October 12.
- The iPhone has not run since `6c940cf` (October 7), so Google's October 8 iOS
  rebuilds have run only in the simulator.
- Run B5 on the final code, after S1's runtime changes.

### B6. Ruleset (optional)

All 16 required checks report since October 11. The same edit could require
the Decision, Retrieval and Bundled models jobs (rules list matrix jobs by
their expanded names, such as `Decision / package / macos-15` since R2) and
rename the jobs still called "official Android SDK" and "official iOS SDK"
(R7). R2 renamed Decision's and Retrieval's checks (a reusable workflow names
them `<caller> / <job>`), so the ruleset can be edited once.

### B7. Publish

As `CONTRIBUTING.md` describes: remove `publish_to: none` and the
`(unreleased)` marks in one commit, run `publish_check.py` and
`test_bundled_models.py`, publish `mediapipe_core`, switch the five families
from `path:` to `mediapipe_core: ^0.1.0`, then publish them. Dry runs only
until then; never `--force`.

## Shipped cleanups

These change what pub.dev receives. They land before 0.1.0 with the rest, so
every helper they add to core freezes with 0.1.0. Keep those helpers few, in
core's family-facing libraries (`native_structs.dart`,
`platform_interface.dart`, `web_task_bridge.dart`) plus one new
`task_worker.dart`, each documented as not for applications; B4's snapshots
show every one.

### S1. Duplication in the families

| What | Copies | Size today |
|---|---|---|
| Worker isolate lifecycle: `Isolate.spawn` with `onError` and `onExit`, ready and exited completers, an id-keyed pending map, the same `_receive` and `_fail`, a loop that closes the task in `finally` | Six: text `text_task_worker.dart` (223 lines), vision `vision_task_worker.dart` (216) and `native_interactive_segmenter_runner.dart` (167), Decision `native_runner.dart` (157), Retrieval `native_runner.dart` (161), and the lifecycle of audio's stream worker (`native_audio_stream.dart:27-46`, `:58-64`, `:84-99`). Decision's and Retrieval's differ only in names. Audio's clips classifier instead spawns an isolate per request (`native_audio_classifier.dart:146-148`). | 967 lines |
| Serial request queue (`_tail`, `_disposing`, drain-then-close) and the error conversion around it | Six owners: `decision_maker.dart:36-37`, `:143-151`, `:170-184`; `retrieval_tasks.dart:42-43`, `:124-149`; text `text_task_runner.dart:158-186`; audio `runner.dart:62-63`, `:84-110` and `native_audio_classifier.dart:134-158`; vision `mediapipe_vision_web.dart:151-152`, `:224-242`, `:309-311`. The conversions disagree: audio keeps `cause`, Decision and Retrieval pass any `MediaPipeException` through, text wraps anything else without a cause (`text_task_runner.dart:38-40`), vision converts inline. | 143 to 152 lines |
| FFI status helper: call with an error out-parameter, throw `TaskException`, free Google's string | Seven: text's `checkTextStatus` and the summarizer's and proofreader's `_checked`, audio `checkedNativeCall` (which frees only on failure and has no `finally`), vision `checkedCall`, Decision `_check` (with its UP-053 rewrite), Retrieval `_check` | 114 lines |
| Nullable `Pointer<Char>` to `String?` | Seven: three in text, audio, Decision, Retrieval, and vision's, which turns an empty string into null (Python parity) | 22 lines |
| Filling and copying core's own structs | Base options from `TaskOptions` into core's `MpBaseOptions`: six (text `fillTextBaseOptions` at `classic_text_runtime.dart:48-70`, the proofreader's and summarizer's `:25-31`, Decision `native_decision_maker.dart:57-71`, Retrieval `native_retrieval.dart:61-75`, audio `native_audio_classifier.dart:66-79`). Classifier options into core's `MpClassifierOptions`: two (`classic_text_runtime.dart:72-97`, `native_audio_classifier.dart:79-98`), with the same string-array loop as vision's `visionOptionStrings` (`native_vision_task.dart:243-250`). `MpClassifications` into `Classifications`: two (`native_text_classifier.dart:65-90`, `native_audio_classifier.dart:225-252`). | 190 lines |
| `MpEmbedding` and `MpEmbeddingResult` | Hand-written in text's `embedding_gemma_bindings.dart:34` and `retrieval_bindings.dart:19` | 42 lines |
| A native handle closed exactly once (test, clear, then call the checked close) | Seventeen `close()` bodies: Decision, five in text, eleven in vision (the ten tasks' and `native_interactive_segmenter.dart:137`) | About 122 lines |
| WebGPU adapter probe | `_webGpuAdapter` in `mediapipe_decision_web.dart:32` and `mediapipe_retrieval_web.dart:32`, and `webGpuAdapterPrefix`, `_softwareAdapter` and `_hardwareWebGpu` in both `capabilities.dart` files (`:51`, `:20`) | 90 lines |
| Script loader | Vision's `_workerResult` and `_load` (`mediapipe_vision_web.dart:155-185`) repeat core's `_reported` and `_loadBridge` (`web_task_bridge.dart:61-93`) with another script | 31 lines |
| Struct layouts in generated code | Vision's ffigen output redefines five structs core already declares (`vision_bindings.dart:1353`, `:1434`, `:1458`, `:1483`, `:1507` against `native_structs.dart`) | 172 lines |
| `"$os/$arch"` target string | `native_decision_maker.dart:14`, `native_retrieval.dart:15`, `classic_text_runtime.dart:15`; core computes it only inside its async platform snapshot (`platform_io.dart:69`) | 6 lines |

**Fix, in steps:**

1. **FFI kit in core** (`native_structs.dart`, next to the structs):
   `checkNativeStatus(call, errorFree, {failure})`, `nativeString(value,
   {emptyIsNull = false})`, `nativeStrings(arena, values)`,
   `fillBaseOptions(target, arena, {modelPath, modelBuffer, ...})`,
   `fillClassifierOptions(target, arena, settings)`,
   `copyClassifications(heads, count)`, and the two embedding structs. Each
   family passes its own `errorFree`; Decision keeps its UP-053 rewrite in a
   `failure` callback; audio passes its retained model buffer (freed on
   close), which the helper neither copies nor frees. Vision keeps its
   empty-string rule, and after step 6 uses the fill and copy functions too
   (base options `native_vision_task.dart:38-62`, classifier filters
   `:405-422`, categories `:90-112`), keeping its GPU admission and library
   loading outside them; Object Detector holds the classifier fields directly
   on its own options struct (`native_object_detector.dart:28-45`) and copies
   them from the helper's. Add core tests with fake out-pointers (zero,
   nonzero, null and empty messages, a throwing `failure`). About 368 lines
   become 150 to 200; net about 170 to 220. The target string stays as it is
   unless a synchronous getter is wanted anyway. **Done on
   `chore/oct12-combined`, but for vision's fill and copy, which wait for
   step 6:** all eight are in core with tests, and vision uses
   `checkNativeStatus`, `nativeString` and `nativeStrings`. Audio no longer
   keeps its model bytes until close, and its options go to the stream's
   worker as they are, as text's and Decision's do: Google's C API copies the
   model when it creates a task (`base_options_converter.cc`), and a check
   that zeroed and freed audio's buffer right after create kept every one of
   the speech clip's 2,605 scores. So `fillBaseOptions` takes no buffer of the
   caller's.
2. **Close-once handle:** `NativeTaskHandle<T extends NativeType>` (`value`,
   `close(release)`), clearing the pointer before the callback. Net about 50.
   **Measured and dropped:** it added 18 lines; see [Keep](#keep).
3. **Core web helpers** (`web_task_bridge.dart`, `platform_interface.dart`),
   **done on `chore/oct12-combined`:**
   `readWebGpuAdapter()`, `hasHardwareWebGpu(TaskPlatform)` and
   `loadPackageScript(package, asset)`; the prefix and the regex become
   core-private, which removes `webGpuAdapterPrefix` from both families (B3).
   Registration must still precede the first capability query
   (`currentTaskPlatform` caches). Net about 62.
4. **Serial queue and one error mapping:** `SerialTaskQueue` (`add<T>`,
   `close`, `closing`) and `taskException(Object)` in `platform_interface.dart`,
   keeping the cause and passing `MediaPipeException` through, so every family
   reports errors the same way. A failed request must not poison the next. Net
   22 to 80, depending on how much decoding moves. **Done on
   `chore/oct12-combined` for the six queue owners, net 51:** nothing read
   `closing`, so the queue has `add` and `close` only, and decoding moved
   inside each request, so a malformed result is a `TaskException` too.
   Text's worker passes core's mapping on, so a `RuntimeUnavailableException`
   no longer turns into a `TaskException` there. Vision's workers and live
   stream, and audio's stream results, keep their own conversion for step 5:
   their failures cross isolates into fields typed `TaskException`, which the
   audio stream documents.
5. **One worker isolate in core** (`task_worker.dart`, native only):
   `WorkerTask<I, R, U>` (`run`, `stream`, `close`) and `TaskWorker.start(name,
   options, create)` with `run`, `stream`, `dispose` and `failure`. Text's
   worker is already generic and the superset (streams with cancellation).
   Vision wraps its native task in a reopening `WorkerTask` for the GPU frame
   budget and reads `failure` for its checks; the segmenter sends its two
   commands; Decision and Retrieval become about 20 lines each; audio's stream
   worker reuses the spawn and exit channel and keeps its close sequence. Write
   core's tests with a fake `WorkerTask` first: worker death, creation failure,
   dispose order and cancellation, for all six, with no native library (today
   Decision's and Retrieval's copies run only in model-gated tests). Then move
   one family at a time with every platform's suites, debug and release, the
   iPhone and Test Lab. 967 lines become 415 to 600; net 370 to 550.
   **Done on `chore/oct12-combined` for five of the six, net 487 (the iPhone
   run is still to come):** core's `TaskWorker` is extended by text's,
   Decision's and Retrieval's runners, which add their family's interface,
   and held by vision's two, so it needs neither `failure` nor a static
   `start`; vision's checks hear a worker's failure through a callback. The
   GPU frame budget now reopens Google's task before the next frame rather
   than after the last one, which spares a reopening right before close, and
   a failed reopening fails that frame and every later one. The isolate takes
   its name from the task's, so vision's `debugName` parameter is gone.
   Audio's stream worker stays: Google's callback delivers its results
   unasked, while `TaskWorker` answers each request once.
6. **Vision's bindings reuse core's structs:** in `ffigen.yaml`,
   `library-imports` (`package:mediapipe_core/native_structs.dart`) and a
   `type-map.structs` entry per shared struct, then regenerate (ffigen 21
   supports both). Vision's copy helpers switch to core's camelCase fields and
   can use step 1's functions; its host-system mapping
   (`native_vision_task.dart:41-49`) becomes `mp.MpHostSystem.fromValue(mpHostSystem)`
   or goes. Check with `tool/abi_check.cc` and every vision suite. Net about
   127 generated lines. **Measured and dropped:** see [Keep](#keep).
7. **The JS worker scaffolding:** text's, audio's, Decision's and
   Retrieval's `worker.js` repeat the serialized `onmessage` queue and its
   replies, the create, close and closed branches, the `baseOptions` spread and
   `withoutNulls`, and vision's worker (`worker.js:187-201`) repeats the queue.
   The reason the old Keep entry gave for leaving it (a second script from
   core's package path) no longer holds: every family worker already imports
   `verified_runtime.js` from there. Export `installWorkerQueue(run, {reply,
   transfers, target})` and `withoutNulls(settings)` from that module, so no
   new script loads; Retrieval passes its empty-reply mapping and vision its
   transfer and overlay envelope as callbacks, and `withoutNulls` keeps
   `false`, zero and empty strings. The reply protocol then sits in the same
   package as `task_bridge.js`. A scratch prototype kept ordering, failure
   continuation, Retrieval's empty replies and vision's transfers. Net 36 to
   43 lines. **Done on `chore/oct12-combined`, net 35:** the five workers
   call `installWorkerQueue`, with Retrieval's empty reply and vision's
   transfers and overlay flag as its `reply` and `transfers`, and four take
   `withoutNulls` from core. Nothing set a `target`, so there is none. The
   create, close and closed branches stay in each worker: their bodies
   differ, and Retrieval's and vision's keep state beyond one task.
8. **Smaller ones:** Retrieval's embedding decoder
   (`results/decoders.dart:23-57`) repeats core's `decodeEmbedding`
   (`sdk_json.dart:34-53`, which text and vision use) with stricter rules: an
   empty unused vector counts as absent, exactly one representation must
   remain or it throws `TaskException`, and `headName` is cast strictly. Keep
   those rules in a short wrapper over core's decoder (net about 11; no new
   export). One `pluginNotRegistered(package)` for the five
   `native_stub.dart` messages and the two capability strings (36 lines, net
   about 14). In text, a `runClassicTextRequest<T extends Struct, R>` like
   vision's `runVisionRequest` for the language detector and classifier, and a
   shared base for the proofreader and summarizer (net about 50, optional).
   **Done on `chore/oct12-combined`, but for the optional text items:**
   Retrieval's decoder is a 12-line wrapper over core's (net 22), and core's
   `pluginNotRegistered(package)` serves the five stubs and both capability
   reasons (net 10). The text items stay: Dart's FFI cannot allocate a struct
   from a type parameter, so each request would still pass its own
   allocator, as vision's do, and the shared runner saves about 2 lines; the
   proofreader and summarizer differ in every struct and call, so a shared
   base would be mostly callbacks.

### S2. Small dead code and leftovers

**Done on `chore/oct12-combined`,** the macOS wheel branch with B3's wheel
fold. As found:

- `bundleWheelRuntime`'s macOS branch (`family_runtimes.dart:452-454`) cannot
  run: `wheelRuntimes` pins only `windows/x64`. It goes with B3.
- Decision declares `meta: ^1.18.0` (`pubspec.yaml:37`) and never imports it:
  the only unused dependency in the repository.
- `runningInIosSimulator` (`platform_io.dart:76-78`, `platform_stub.dart:26-27`)
  is exported through `platform_interface.dart:8`, so it is public API, but its
  only caller is `platform_io.dart:72`. Inline `_iosSimulator`.
- `bin/prefill_assets.dart` ships as `dart run mediapipe_core:prefill_assets`,
  a public command, but only `packages/mediapipe-core/tool/mirror_runtime_assets.py:96`
  calls it. Move it to `tool/`, which `.pubignore` already excludes.
- Core repeats the "read `taskPlatformGpuReader`, ignore failures" block
  (`platform_stub.dart:11-18`, `platform_io.dart:59-66`), and
  `bin/web_runtime.dart:7-13` (`_families`) repeats the keys of
  `bundlableFamilies`.

### S3. Stale or bulky shipped files

- `reference_wheels.dart:8` says the references come from the 1.1.0 release
  candidate "until 1.1.0 itself is published". Google published 1.1.0 on
  October 6, and the Decision and Retrieval references use it. Moving the
  older families' references to the final wheel means regenerating every
  vision, text and audio fixture, and `1.1.0rc20260925` is restated in the
  three wheel rows (`:20`, `:32`, `:44`), three generated gallery reference
  files and about ten fixture READMEs. Reword now; re-pin with the next fixture
  regeneration.
- `vision/lib/src/types/face_landmarks_connections.dart` is 2,712 lines and
  42 KB, one pair per line. Eight pairs per line inside `// dart format off`
  make it 364 lines and 33 KB (22% smaller), with the same tokens. Do it in
  the generator (`tool/generate_face_landmarker_reference.py:110-114`). The
  hand and pose tables come from a second generator,
  `tool/generate_landmark_connections.py`; one generator for all three keeps
  the format in one place.

**Done on `chore/oct12-combined`:** `reference_wheels.dart` says 1.1.0 is
published and the pins move with the next regeneration.
`generate_landmark_connections.py` writes all three tables (run on the 1.0.0
environment the files were generated from), about seven pairs per line inside
`// dart format off` through core's `dart_rows`: the face file is 459 lines
and 33 KB, the hand and pose file 55 lines, with the same edges; the face
reference generator no longer writes Dart.

### S4. Retrieval explains an unsupported target with its GPU message

**Done on `chore/oct12-combined`:** a no-library reason for both delegates, as
Decision has, and a test for three unsupported targets. As found:

`retrieval/lib/src/capabilities.dart:73-74` uses `_desktopGpu` as the native
CPU reason, and core uses that reason when the target is missing from the
table (`task_capabilities.dart:120-122`). On `macos/x64`, `linux/arm64` or
`windows/arm64`, Retrieval therefore reports no supported delegate and gives
"Google's retrieval library runs the tasks on the CPU; this package has not
validated a GPU path." as the reason, which `requireDelegate` throws as the
fix. Decision has a separate no-library reason (`decision/lib/src/capabilities.dart:39-42`,
used at `:121-125`). Add one (or one core sentence for both) and a test case
for an unsupported target (`retrieval_unit_test.dart:283-315` covers
supported targets and macOS 13 only).

### S5. `verified_runtime.js` ships in native apps

**Done on `chore/oct12-combined`.** As found:

`packages/mediapipe-core/pubspec.yaml:46` lists `assets/verified_runtime.js`
without `platforms: [web]`, unlike `task_bridge.js` (`:47-48`) and every
family's web assets. Only the web workers import it, so every Android, iOS and
desktop app carries a 45-line JS file it never loads. Add the filter.

## Repository cleanups

Nothing here ships.

### R1. The Universal Embedder page copies the Image Embedder page

`gallery/lib/universal_embedder_page.dart` (522 lines) was built from
`embed_page.dart` (537): 185 of their roughly 355 normalized lines match in
runs of four or more. They share the `_Slot` type, the operation queue,
`_choose`, `_upload`, `_close`, the image slot (`embed_page.dart:428-526`
against `universal_embedder_page.dart:416-511`) and `_similarityCard`. Their
settings panels and `_setSetting` differ (Universal pins one model and
delegate; Image Embedder offers alternate and uploaded models).

**Fix:** `gallery/lib/ui/similarity.dart` with `SimilaritySlot<I>`, an input
slot, `similarityCard(...)` and `chooseImage<I>(...)`; each page keeps its
task, input kinds and settings. A slow decode must not replace a newer choice.
About 120 to 130 lines. **Done on `chore/oct12-combined`:** a `SimilarityState`
mixin on `State`, as R4's `RevisionedState`, since choosing, decoding and
comparing all run through `setState` and `mounted`. It owns the slot, the
operation queue, the open task, `compare` and `closeEmbedder`, the image slot
widget and the status, error and similarity card. The two pages dropped 456
lines for the mixin's 353; both pages' keys and semantics identifiers are
unchanged, and the Universal Embedder page's run row is a `TaskRunRow` too.

### R2. Decision and Retrieval CI

- `retrieval.yaml` (208 lines) copies `decision.yaml` (320): 128 of
  Retrieval's roughly 200 normalized lines match. Each new family so far has
  added another such file.
- The families run their phone tests in different places. Decision has its
  own Android and iOS jobs (`decision.yaml:131-187`, `:188-240`), which repeat
  the setup of `android.yaml` and `ios.yaml`, while Retrieval's two tasks run
  inside those shared jobs (`android.yaml:75`, `ios.yaml:75`).
- Both run `dart analyze --fatal-infos` on three OSes (`decision.yaml:66`,
  `retrieval.yaml:65`) and `flutter analyze` again later, while `main.yaml`'s
  `make analyze` already covers both packages, and analysis does not depend
  on the OS. `web.yaml:69` and `:82` repeat the same for vision, text and
  audio.
- Both run their web job on `ubuntu-24.04` too (`decision.yaml:250`,
  `retrieval.yaml:136`). Hosted Linux has no hardware WebGPU, so those runs
  only check the refusal that `web.yaml`'s Chromium journey also checks, but
  only loosely: `gallery/tool/browser/test_gallery_journey.mjs:164-169` waits
  for the first `/UP-049|UP-052/` text on the page for each refused card, so
  after Decision's card matches, Retrieval's two cards pass without being read.

**Done on `chore/oct12-combined`, the first part:** the journey reads each
refused task's own card ("<title>. <reason>") and checks its reason.

**Fix:** make the journey check each refused card; then one reusable workflow
(`.github/workflows/family.yaml`, `on: workflow_call`, inputs `family`,
`tasks`, `integration-test`, `model-path`, `coverage-tasks`) with two thin
callers; Decision's phone steps in `android.yaml` and `ios.yaml`, as
Retrieval's are; no repeated analysis and no Ubuntu web runs. About 190 to 220
lines. It renames the checks, so it lands before B6's ruleset edit.

**Done on `chore/oct12-combined`, the rest:** `family.yaml` (173 lines, inputs
`family`, `tasks`, `integration-test`, `model-path`, `jobs`) with
`decision.yaml` and `retrieval.yaml` as callers of 35 and 38 lines (494
before). The checks are `Decision / package / macos-15`, `Decision / gallery /
macos/arm64` and `Decision / web WebKit macos-26`, and the same for Retrieval.
Decision Maker joins the phone builds: `android.yaml` runs its test and its
pages in the one-launch suite (`sdk_all_test.dart` now imports
`decision_maker_test.dart` and `retrieval_test.dart`, which skip when the
build bundles neither, so Test Lab's build is unchanged until B5 adds the
tasks), `ios.yaml` runs both files in its loop, and each records a Decision
row. The package jobs no longer analyze (main.yaml's `make analyze` covers
every package) and the web job runs on the two Macs only.

### R3. CI setup repeated

`subosito/flutter-action` with the pinned Flutter appears 25 times across the
workflows, `actions/setup-python` (3.12) 17 times, the Windows hosts-file block
for Google's usage logging (UP-025) 7 times in five workflows
(`bundled-models.yaml:53`, `decision.yaml:52`, `:97`, `desktop.yaml:89`,
`retrieval.yaml:51`, `:96`, `windows-camera.yaml:147`; an eighth match at
`desktop.yaml:80` is a comment), the generative text model cache 3 times, and
14 `apt-get install` lines in several variants (EGL only for FFI hosts, the
Flutter desktop set, the browser camera set, two one-offs). A Flutter bump
edits 25 places.

**Fix:** a local composite action (`.github/actions/setup/action.yml`) with
inputs `python`, `linux-profile` (`none`, `ffi`, `gallery`, `browser`),
`block-telemetry` and `modern-model-cache`, and the versions pinned inside it
only. Steps must follow checkout and keep `shell:` on every run step. About 90
to 150 lines, and one place for version bumps.

**Done on `chore/oct12-combined`:** `.github/actions/setup/action.yml` (inputs
`flutter`, `python`, `linux-profile`, `block-telemetry`, `modern-model-cache`)
replaces the 25 Flutter blocks, 16 of the 17 Python blocks (the Pages
verification job has no Flutter and keeps its own), the 7 hosts blocks, the 3
model caches and 12 of the 14 apt lines; the Linux GPU job's Mesa libraries,
the camera job's loopback packages and the Pages job's ffmpeg stay as their own
one-line steps. `tool/check_repository.py` reads the Flutter pin from the
action. actionlint 1.7.12 reports nothing on the result, as on the previous
workflows.

### R4. Gallery page scaffolding

- **Settings-sheet redraw:** nine pages hold `final _revision =
  ValueNotifier<int>(0)`, bump it in `setState` and dispose it (`audio_page.dart:68`,
  `decision_page.dart:91`, `embed_page.dart:104`, `fish_game_page.dart:95`,
  `live_page.dart:78`, `retrieval_page.dart:78`, `segment_page.dart:55`,
  `text_page.dart:86`, `universal_embedder_page.dart:108`);
  `segment/editor_controller.dart:55` is an `int` for request invalidation,
  not the pattern. `live_page.dart:83` skips the bump on frame rebuilds. A
  `RevisionedState` mixin in `gallery/lib/ui/` with an overridable bump.
  About 37 lines. **Done on `chore/oct12-combined`:** the mixin is in
  `ui/workspace.dart`, and the live page overrides its `bumpsRevision`.
- **Run row and error card:** the Run, spinner and "Done in N ms" row in
  `decision_page.dart:388-411`, `retrieval_page.dart:305-328` and
  `text_page.dart:493-515`, and the error `OutputCard` in five pages
  (`audio_page.dart:527`, `decision_page.dart:415`, `fish_game_page.dart:286`,
  `retrieval_page.dart:332`, `text_page.dart:518`). `TaskRunRow` and
  `TaskErrorCard` in `gallery/lib/ui/components.dart`. About 48 lines. The
  Decision and Retrieval pages share 78 normalized lines in all; these two
  helpers and the mixin cover most of them. **Done on `chore/oct12-combined`;** with the
  mixin, the gallery's `lib/` is 83 lines shorter.
- **Decision pins:** **Done on `chore/oct12-combined`:** `TaskModel.pinned`,
  and a `pin` getter for the three places that rebuilt one. As found:
  `gallery/lib/live/task_models.dart:35-65` hardcodes four
  Decision model pins (path, SHA-256, size) that `DecisionModels` already
  pins, and `decision_page.dart:116` and `fish_game_page.dart:156` rebuild a
  `DownloadAsset` from them. A `TaskModel.pinned(label, DownloadAsset pin,
  bytes)`; sizes and labels stay gallery data.
- **`GalleryTask.downloadsModel`** (`catalog.dart:147`, set at `:426`, `:442`,
  `:473`, `:484`) restates the builder's `downloadedModelTasks`
  (`tool/gallery_builder/lib/models.dart:87-91`). A getter that lists the ids
  would only move the duplication; derive it from that list or test it
  against it.
- **Camera controllers:** `gallery/lib/live/live_camera_controller_native.dart`
  and `gallery/lib/web/live_camera_controller.dart` share 112 normalized lines:
  the frame statistics (`:114-185` and `:139-218`) and `switchCamera`
  (`:219-263` and `:352-397`). A `FrameStatistics` class reusing
  `RecentFrameTimings` (about 38 lines), then camera switching.

A shared Decision model holder for the Decision and Hungry Fish pages is not
worth it (see [Keep](#keep)).

### R5. Test and harness duplication

- **Vision's landmark and segmenter reference tests** repeat their suite and
  their `_image` helpers (`landmark_tasks_test.dart:49-100`, `:262-304`;
  `segmenter_tasks_test.dart:29-78`, `:218-266`). `test/support/vision_fixture.dart`
  reads a different JSON schema, so parameterize it rather than swap it in.
  The variable they read, `MEDIAPIPE_OFFICIAL_MACOS_LANDMARK_RUNTIME`, is
  named after the retired macOS engine and is read in four test files
  (`image_tasks_test.dart:199`, `:295`, `landmark_tasks_test.dart:26`,
  `object_detector_test.dart:26`, `segmenter_tasks_test.dart:24`) and written
  by `tool/test_macos_references.py:116` and `prepare_gpu_reference.py`;
  rename it with every writer. About 60 lines.
- **The gallery's SDK integration tests** repeat their per-delegate harness
  (`sdk_detection_tasks_test.dart:57-91`, `sdk_embedder_test.dart:45-60`,
  `sdk_face_landmarker_test.dart:24-31`, `sdk_hand_landmarker_test.dart:60-78`,
  `sdk_landmark_tasks_test.dart:57-93`, `sdk_segmenter_test.dart:58-115`): a
  `forDelegates(...)` helper with a GPU-policy parameter (the interactive
  segmenter's stricter policy stays its own). About 78 lines. Six of them
  repeat the same `_model` loader, five tests and probes repeat an `asset`
  loader (`audio_task_test.dart:19-22`, `runtime_test.dart:75-78`,
  `sdk_text_audio_test.dart:30-33`, `gallery/lib/audio_page.dart:116-119`,
  `gallery/tool/web_text_audio_probe.dart:156-159`), and nine repeat a
  `_report` printer. About 33 lines.
- **Small helpers recopied:** `expectFollows` in three tests
  (`text_proofreader_test.dart:84-96`, `text_summarizer_test.dart:77-89`,
  `gallery/integration_test/sdk_modern_text_test.dart:559`); `_gridError` in
  `sdk_interactive_segmenter_test.dart:203-222`, which
  `confidenceGridError(...).mean` in `support/mask_grids.dart` already
  computes; `_settle` and `_screen` in the journey test, `support/delegate_control.dart`
  and `gallery/test/audio_page_test.dart:310`; and the constant overrides of
  the fake `CameraPlatform`s (`support/supplied_camera.dart:194-211`,
  `gallery/test/support/scripted_camera.dart:116-133`). About 60 lines.
- **The receipt-checked reference loader** is written four times, twice in
  audio (`audio_classifier_test.dart:22-59`, `audio_stream_runtime_test.dart:35-74`,
  `text/test/support/classic_text_reference.dart:20-60`,
  `vision/test/support/face_reference.dart:94-125`): one verifier with
  explicit schemas, keeping every negative receipt test. About 26 lines.
- **The coverage-matrix tests** are done ([The guards](#the-guards-step-1)).

**Done on `chore/oct12-combined`, in part:** `cpuReferenceSkipReason` in
`face_reference.dart` replaces the four inline macOS checks, whose variable is
now `MEDIAPIPE_SAME_HOST_CPU_REFERENCES`, set by `test_macos_references.py`
(its only writer); `pixelsImage` in `vision_fixture.dart` builds the blank,
RGBA and rotated inputs for the landmark, segmenter and face suites (checked
identical to the three copies over 90 cases); audio's two receipt-checked
loaders are `loadSameHostReference` in `test/support/same_host_reference.dart`;
text's `expectFollows` lives in `modern_text_reference.dart`. In the gallery,
`loadAssetBytes` and `loadBundledModel` in `bundled_model_assets.dart` serve
the six `_model` and five `asset` loaders (the audio page and the web probe
included), `logRecord` in `support/device_log.dart` the nine `_report`
printers, `confidenceGridError(...).mean` the interactive segmenter, and
`settle` and `screenText` in `delegate_control.dart` the journey test. Left as
they are: the `forDelegates` harness (each loop's refusal policy, exception
type and cleanup differ, and nothing here can run the result before the next
device run), text's and vision's receipt loaders (other receipt schemas), the
widget tests' `_settle` (a frame-free wait, not the same) and the two fake
`CameraPlatform`s (different test trees, orientations and previews).

### R6. Maintainer tools

- **Vision's reference generators:** the face and object detector generators
  share 92 of about 135 normalized lines in runs of four or more (`record` and
  `gpu_image` are exact copies), and the image and segmenter generators share
  `image_for` and the JSON envelope. A `tool/reference_support/vision_cases.py`
  with each task's spec. 85 to 130 lines.
- **Python helpers copied across tools:** `digest` (12 copies), the logged
  `run` (five, four with the `dart.bat` workaround), the venv and pinned-wheel
  setup (seven) and the UP-032 ctypes layout fix (two). They belong beside
  `packages/mediapipe-core/tool/official_wheels.py`, which about 15 scripts
  already import. About 70 lines.
- **`generate_segmenter_tasks_reference.py`** keeps two 1.0.0 workarounds
  (`:35-40`, `:148-152`): `mask_array`'s value-by-value copy and the skipped
  GPU VIDEO references. Re-test both with the pinned 1.1.0 wheels before
  removing them.
- **The Makefile:** `make test` runs `test_decision` and `test_retrieval`
  since the guards. `generate` calls `generate_text` (`Makefile:47-49`), which runs an ABI test
  and generates nothing: rename it. `test_audio_web`, `test_vision_web`,
  `test_embedding_macos` and `test_modern_text` have no caller in the
  repository (CI runs the scripts directly) but are contributor shortcuts;
  keep them documented or remove them deliberately.
- **`gallery/tool/windows/vcam/vcam_host.cpp`**: `--auto`, `--all-users` and
  `--system` (`:407-410`) parse and work, and the host waits on its stop event
  (`:146-153`), but nothing in the repository passes those flags or sets the
  event (CI runs plain `start`). `video_frames.podspec` is the CocoaPods
  fallback for contributors without Swift Package Manager. Keep both (decided
  October 12) and label each as unused by CI.

**Done on `chore/oct12-combined`, in part:** `digest` and the logged `run` live
in `packages/mediapipe-core/tool/tool_helpers.py`, `pinned_venv` in
`official_wheels.py` and the UP-032 layout fix in core's
`official_embedding_layout.py` (`use_header_embedding_layout(family)`); the
twenty copies are gone and every caller was run once (the classic text, CPU,
image tasks, audio and EmbeddingGemma generators). `run` defaults to a 3600 s
timeout where some copies had 900 or 1800. `generate_text` is `check_text_abi`,
and the four contributor shortcuts are labelled in the Makefile, as are the
vcam flags and the podspec. Not done: the vision generators' `vision_cases.py`
and the segmenter generator's two 1.0.0 workarounds, which wait for a
regeneration on the pinned wheel.

### R7. Docs that drifted

- `packages/mediapipe-core/tool/PER_FAMILY_RUNTIMES.md:3` still says "Status on
  2026-10-07: on `chore/debloat`", and its "Before merging" section (`:124`)
  lists work for a merge that happened on October 7. Retitle it for the
  release and keep its open entries: the iPhone, release builds with an App
  Store validation of the iOS frameworks, and notices.
- "Official SDK" and "Objective-C adapter" wording outlived the switch to
  Google's C libraries: six gallery integration test headers, step and job
  names in `android.yaml`, `ios.yaml` and `android-face-testlab.yml`, and
  `UPSTREAM.md:55-56`. Reword comments and steps now, and rename jobs with the
  ruleset (B6).
- `packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md:28` still gives
  Face Detector GPU on Android and GL ES on Linux, which `capabilities.dart`
  withdraws (UP-046), and Holistic GPU on Android (UP-026, `:33`). Replace its
  support table with one generated from the capability queries and
  `tool/coverage/matrix.json`.
- Bundling and offline builds are explained three times, already
  differently: the core README, `doc/platform_setup.md:120-175` and
  `MODEL_BUNDLING.md:38-109`. Keep the core README's sections, link to them,
  and keep `MODEL_BUNDLING.md`'s design history. Package READMEs keep their own
  short bundling snippet, since each stands alone on pub.dev. About 130 lines.
- `upstream-issues.md:83` and `:154` name `lib/src/io/holistic_landmarker.dart`
  and `image_segmenter.dart` (now `native_holistic_landmarker.dart` and
  `native_image_segmenter.dart`), and `:1054` points to a probe in an ignored
  local `build/` folder.

**Done on `chore/oct12-combined`, in part:** "Before the release" keeps the
iPhone, release builds and notices entries and sums up what was done; the test
headers, step names and `UPSTREAM.md` say mediapipe_vision on Google's vision
library; the status table's Face Detector and Holistic rows and its library
rows follow `capabilities.dart` and the 1.1.1 library by hand (a generated
table is not done); `doc/platform_setup.md` and `MODEL_BUNDLING.md` link to the
core README's bundling sections; `upstream-issues.md` names the current files.
The job names wait for the ruleset (B6).

### R8. Generated data layout

- Retrieval's `test/fixtures/embedding_gemma_2_text_vision_reference.json` is
  10,468 lines: 13 vectors of 768 numbers, one number per line, written by
  `tool/generate_reference.py:164` with `json.dumps(reference, indent=1)`.
  Decision's generator does the same (`:106`). One line per numeric vector
  gives 471 lines and 124,567 bytes instead of 156,878, with identical decoded
  JSON.
- The gallery's `official_mask_references.dart` (3,200 lines) and
  `official_detection_references.dart` (2,240, including two 1,024-number
  embedder vectors) put each value on its own line. Rows emitted inside
  `// dart format off` by `gallery/tool/generate_sdk_references.py:130-138`
  and `:169-173` make them 258 lines each.
- This changes line counts and bytes, not files or coverage, and none of these
  files is in a package archive. Vision's JSON fixtures could follow if the
  count matters.

**Done on `chore/oct12-combined`:** `compact_json` in core's `tool_helpers.py`
writes a list of numbers on one line; Retrieval's and Decision's generators use
it, and their three fixtures were rewritten with it (decoded JSON identical:
10,502 to 505, 1,606 to 68 and 529 to 469 lines). `generate_sdk_references.py`
packs the embedder vectors, the mask grids and the stroke histories into rows
inside `// dart format off` with core's `dart_rows`, and formats its output
itself; the masks file is 380 lines and the detections file 514, with the same
values. Decision's `embedding_gemma_2_text_vision_reference.json` has no
generator in the repository and was left alone.

### R9. Hungry Fish leftovers

`FishGame.waiting` (`fish_game.dart:547-548`) has no reader (keep the `_waiting`
field it returns, which gameplay uses), and `_SeaPainter.colors`
(`fish_game_page.dart:523`) is stored and never read.

**Done on `chore/oct12-combined`:** both removed; `_waiting` stays.

### R10. Coverage recording repeated in CI

`tool/coverage/record.py` runs 37 times in eight workflows and its output is
uploaded by 17 `coverage-*` artifact steps, whose naming
`coverage-gate.yaml` depends on. One composite action
(`.github/actions/record-coverage`, inputs `suite`, `platform`, `delegate`,
`tasks` and `outcome`) records and uploads. About 30 lines, and one place for
the artifact convention.

**Done on `chore/oct12-combined`:** `.github/actions/record-coverage` (inputs
`suite`, `platform`, `delegate`, `tasks`, `outcome`, `tier`) runs the recorder
and uploads `build/coverage/<suite>.json` as `coverage-<suite>`, one artifact
per suite, which the gate's `coverage-*` pattern collects as before; the 35
record steps call it and the 17 upload steps are gone. The emulator's modern
text outcome and Test Lab's GPU task list come from small output steps.

### R11. One model download tool per family

Fourteen `packages/*/tool/download_*.dart` scripts (179 lines) each call
`downloadVerified(XModels.x, File('models/<name>'))` and print; none does
anything more. One `tool/download_models.dart` per family taking `byName`
keys (defaulting to the family's test set; every default file name is already
the URL's last segment) replaces them, and the Makefile's `models` targets and
CI steps pass names. About 55 to 120 lines.

**Done on `chore/oct12-combined`:** `tool/download_models.dart` in each
family (128 lines for the five, against 181) takes `byName` names and saves
each model under its URL's last segment, which `downloadVerified` reuses when
the hash matches; vision, audio and Retrieval default to every model, text to
the three classic models and Decision to Laya S256. The Makefile's model
targets, six workflows, `tool/test_text_audio.py` and four docs pass names.
Run against the models on disk, every family kept the same file names.

### R12. Small tool and test helpers

- `tool/check_docs.py` checks the docs' Dart samples and links, not their
  `hooks.user_defines.<family>.models` lists; check those names against each
  `byName` (adds about 20 lines).
- `gallery/tool/browser/test_browser.mjs` loads Google's official runtimes in
  seven evaluations (vision at `:117-120`, `:260-263`, `:294-297`, `:330-333`,
  `:380-383`; text at `:958-961`; audio at `:1020-1023`). One init-script
  helper reading `pin.package`. About 3 to 12 lines.
- Five package `analysis_options.yaml` files re-enable
  `public_member_api_docs`, which the shared `packages/analysis_options.yaml`
  they include already enables (15 lines).
- Three generated consumer apps repeat the arm64-only `AppInfo.xcconfig` edit
  and the macOS deployment-target bump
  (`packages/mediapipe-core/tool/test_bundled_models.py:131-141`,
  `packages/mediapipe-task-text/tool/test_embedding_macos.py:133-136`,
  `packages/mediapipe-task-vision/tool/test_flutter_macos.py:59-64`): one
  `configure_macos(...)` beside `consumer_packages.py`. About 7 lines.

**Done on `chore/oct12-combined`:** `tool/check_docs.py` parses each family's
`byName` and fails on a model name a docs sample lists that the family lacks
(five docs list names today); `window.officialTasks(family)` in the browser
test's init script loads Google's runtime at the package's pin for the seven
evaluations; the five `analysis_options.yaml` files are one `include` line;
`configure_macos(app, deployment_target:)` in `consumer_packages.py` serves
the three consumer-app tools.

### R13. Gallery operation queue and model selection

- Three `_enqueue` bodies (`live/live_camera_controller_native.dart:187-195`
  and `live/video_file_controller.dart:90-97`, identical;
  `web/live_camera_controller.dart:287-294`) and the two similarity pages'
  operation tails repeat one serial-operation pattern: an `OperationQueue` in
  `gallery/lib/ui/`. About 7 lines; one concurrency policy.
- Four pages repeat model choice, upload and status handling
  (`audio_page.dart:343-375`, `embed_page.dart:267-322`, `live_page.dart:348-403`,
  `text_page.dart:311-336`): a `ModelSelection` controller in
  `gallery/lib/ui/`. About 13 lines; one place for the selection behavior.

**Done on `chore/oct12-combined`:** `OperationQueue` in
`gallery/lib/live/operation_queue.dart`, used by the three controllers and
the similarity mixin; `ModelSelectionState`, a mixin on `State` in
`live/task_models.dart` next to `downloadModel`, whose `modelChanged` hook
each of the four pages implements (the live page sets its controller's model
loader there). Net about 130 lines fewer.

### R14. Family API snapshots repeat core's

Done in [the guards](#the-guards-step-1): each family's app-facing snapshot is
a delta from core's.

### R15. Alignment metadata in Dart and JS

The face and hand mirror-partner maps and the median and outlier tolerances
live in `gallery/integration_test/support/alignment_oracle.dart:43-44`,
`gallery/lib/live/live_subjects.dart:83-105` and
`gallery/tool/browser/test_browser.mjs:22`, `:26`, `:102-106` (whose comment
says it copies the Dart criterion). One spec both read or are generated from,
keeping the browser's thumb-tip override and the two independent comparison
algorithms. It adds about 29 lines, for one place to edit.

**Done on `chore/oct12-combined`:** the web live view already published its
probes for the browser oracle, so it now publishes their mirror partners
too (`data-partners`), and `test_browser.mjs` reads them from the page
instead of carrying both maps. The tolerances stay in the two oracles, since
the Dart one runs on devices, and `tool/check_repository.py` fails if the
pairs differ.

## Keep

The scans flag these, and they stay:

| What | Why it stays |
|---|---|
| JSON reference fixtures and binary fixture inputs | Google's oracle outputs and their inputs. Every fixture has a reader, and `.pubignore` keeps them out of the archives. |
| Core's `third_party/NOTICE` and `LICENSE`, vision's `third_party/OPENCV_CAROTENE_NOTICES` | Required notices (B2). |
| Text and audio stream bridges (`native/*_bridge.c`, `.h`) | The family hooks compile them, and Dart binds every exported function. They differ (per-request userdata against 64 locked slots), so they stay two. |
| Vision's Android plugin | `gpuRenderer` has a Dart caller (`mediapipe_vision_android.dart`). |
| Browser worker `preload` and `stats` messages | Called by name from `vision/assets/bridge.js` and the browser tests. |
| Vision's `assets/bridge.js` beside core's `task_bridge.js` | Vision's also handles frames and overlays (`task_bridge.js:4`). |
| The five `runtime.json` files, and their `files` arrays | Same shape, different packages, files and integrity hashes. Each `files` array repeats its `sha384` keys (`web_runtime_host.dart:25` checks they match), but dropping it changes a schema the Dart reader and the tests share, for 45 lines. |
| FFI struct fields Dart never reads, ffigen's `$allocate` helpers and `MpSegmentationOptions` | The C layout and the generator need them. |
| The private `macosGpu` parameter | Holistic omits it to keep its macOS GPU withdrawn (UP-026). |
| Public API used only by tests or not at all: `delegate` and `runningMode` on every task, the hand-landmark finger lists, `BrowserOverlay.detach`, `MediaPipeException.cause`, `TaskCapabilities.supportedTargets`, `Matrix.at`, Decision's batch calls, Retrieval's delete calls | Google-parity API and the conventions `tool/api_parity` checks. Coverage gaps, not bloat; B3 names the Retrieval calls nothing runs. |
| The classifier option fields in six option classes; `NormalizedLandmark` and `Landmark`, and vision's two typed landmark copies (`native_vision_task.dart:276-310`) | Each documents its own task, and Google has two distinct landmark types; a generic copy would add lines. |
| `LiveCameraView.showConnections` and `showPoints` on native; the controllers' timing getters; `bundled_model_assets.dart` | The web view behind the same conditional export uses the first two; the performance and integration tests and `gallery/tool` probes read the others. The gallery's bundled-model map lists three families because Decision's and Retrieval's models download on demand. |
| `bundled_model_stub.dart`, `support_directory_stub.dart` | The `dart.library.ui` stubs for pure-Dart users of core. |
| `reference_wheels.dart` in core's `lib/` | Tests in every package import it; moving it out would need a shared test package. |
| Fixture generators, release and mirror tools, `check_docs.py`, `tool/abi_check.cc` | Run by hand, or by `make test_vision`. |
| Root and package `MIGRATION.md`; skipped tests; gallery samples, fonts and platform scaffolding | Readers exist; the skips are still meaningful; all referenced. |
| Gallery parameters only ever given their default | Making them constants removes no code. |
| One base class for the vision task classes, or any whole-task unification | The ten live-stream task classes (997 lines) are alike in shape, but a public base would have to expose the internal `VisionTaskRunner` to subclasses in other libraries, and the per-task docs on `results` and `droppedFrames` would turn generic. Measured across every family's wrappers, options and capabilities, unification adds lines. S1 takes the shared plumbing instead. |
| The 20 `query*Capabilities` wrappers | Two lines each and public API; the shared logic already sits in `_visionTaskCapabilities`, `_onEveryRuntime` and `_generative`. |
| A generic web plugin layer and JSON backend | The four adapters already share `WebTaskWorker`; a generic layer adds about as much as it removes. |
| A generic hook | The hooks are 12 to 42 lines and already call core; sharing the text and audio bridge builder (10 lines each) would make core depend on `native_toolchain_c`. |
| A synchronous `"$os/$arch"` getter on its own | Three two-line copies; a new export and stub cost more. |
| A close-once task handle (S1 step 2) | Tried on `chore/oct12-combined` across all 18 `close()` bodies: 222 lines added against 204 removed. Each close shrank by three lines, but every use of a handle gained `.value`, which re-wraps native calls (one of Hand Landmarker's grew from two lines to seven), and the class itself is 14. The copies already clear the pointer before Google's close, so it fixed nothing. |
| Vision's bindings on core's structs (S1 step 6) | Tried on `chore/oct12-combined`: with the seven shared structs mapped to core's in `ffigen.yaml`, ffigen 21 drops their definitions but now writes a `$allocate` helper for every task's options struct, which it skips while a member is one of its own structs, so the generated binding grew by 42 lines. Vision's fill and copy helpers would shrink by about 50 to 60 on core's, a net of 10 to 20 for a regenerated binding, and vision's structs would then come from core's hand-written copies rather than from Google's headers. |
| One model holder for the Decision and Hungry Fish pages | They share `_pin` and the create call, but Hungry Fish memoizes an in-flight open, runs a loading clock and words its status differently; a holder with callbacks costs more than the copies. R4 takes the pins. |

## Suggested order

Everything before 0.1.0, one branch and pull request at a time. Every pull
request runs the full suites; the runtime one also the iPhone and Test Lab, in
debug and release.

1. **Guards (day 1), done on `chore/oct12-combined`:** B4's snapshots of
   every public library (with R14's delta format), the family inventory,
   `make test` and `make models` for six packages, the pin checks, the
   bundled-models test for every family, and R5's coverage-matrix tests for
   every family. Every later pull request then shows its API changes and
   cannot miss a family.
2. **API trims and release docs (days 1 to 2), done on
   `chore/oct12-combined` but for the Retrieval tests' browser cases, which
   step 8 adds:** B3 (internal constants, model constants, the wheel fold,
   `VisionResult`, and the Retrieval audio and insert tests or holding those
   calls back), S1 step 3, S2, S4, S5 and R4's Decision pins. B1 and B2 are
   done.
3. **FFI kit (days 2 to 3), done on `chore/oct12-combined`:** S1 steps 1,
   2 and 8. Step 2 was measured and dropped, as were step 8's optional text
   items.
4. **Runtime plumbing (days 3 to 5, the riskiest):** S1 steps 4, 5 and 7.
   Core's tests with a fake worker task come first; then one family at a
   time. Steps 4, 5 and 7 are done on `chore/oct12-combined`, but for the
   iPhone run.
5. **Generator (day 6):** S1 step 6, with the ABI check and every vision suite.
   Measured and dropped on `chore/oct12-combined`.
6. **CI (days 6 to 7):** R3 and R10; the journey's refusal check; R2; then
   B6's ruleset edit with the new check names.
7. **Gallery (days 7 to 8):** R1, R4, R13, R15.
8. **Tests, tools and docs (days 8 to 9):** R5, R6, R7, R9, R11, R12, and S3's
   wording.
9. **Layout (day 9):** R8 and S3's compaction, through their generators.
10. **Then:** B5 on the final code (with `sdk_all_test.dart` importing the
    Decision and Retrieval tests), B6 if not done, and B7.

That is about ten working days, with slack for CI rounds (about 50 minutes
each) and flaky browser runs.

## How this was checked

At `ebe8ffd`, on clean `git archive` exports, with `flutter pub get
--offline` in every Dart package and the gallery prepared for `macos/arm64`
with every task:

- **Reference scan:** a resolved-AST scan (analyzer 14.5) of 403 Dart files
  and 5,180 declarations, run with the native and the web `dart.library.*`
  sets (both with `dart.library.ui`) and merged, with zero resolution errors.
  Uses inside a declaration's own body, `@override` members, operators and
  enum values are excluded. Each declaration is classed as unused, used only
  by tests and tools, or used by production code; public API is what the
  packages' libraries export. Re-run on October 12 with the same result.
- **Clone scans:** normalized line windows of 6 and 8 lines over every source
  file (619 files: Dart, JS, Python, YAML, shell, native, Swift, Java, Make,
  CMake and docs), with no changed-file filter, and a 10-line scan with
  identifiers and literals collapsed to catch renamed copies.
- **Function-level hashing:** every Dart function, method, constructor and
  class (analyzer token streams), every Python function (`ast`) and every JS
  function (lexical), hashed exactly, with identifiers renamed consistently,
  and by 6-gram similarity for near copies; every cluster was then read.
- **Sizes:** the "today" counts are measured line ranges; "after" counts are
  estimates of each helper plus its call sites, and where two sizings differ
  the plan gives the range.
- **Re-checks:** every open item from the October 9 status and both October 8
  audits, and every new finding, by file and line at `ebe8ffd`. The Retrieval
  message (S4) was confirmed by running the capability query on the export;
  the R8 and S3 layouts by checking that the reformatted data is identical.
- **Dry runs:** `publish_check.py` on the export with Decision and Retrieval
  added to `FAMILY` (the repository's copy is unchanged), `--dry-run` only.
- **GitHub:** the rulesets, #84's checks and Test Lab's run history.

**Limits:** string-based dispatch (method channels, JS worker messages,
`registerWith`, `.index`) is invisible to the scans and was checked by hand.
Savings are estimates. Nothing was built or run beyond `pub get`, the dry
runs and one capability query.

## The first pass (#77)

Done and merged as `7517e9a` on October 7 (squashed as `3ece0dc`; 18 checks
passed, the 3 deploy checks skipped). At `ebe8ffd` nothing it removed has come
back: vision has one ffigen config and one bindings file, no "official
runtime" flag exists, core vendors 31 headers, and every package's
`.pubignore` keeps models, `tool/`, `test/`, `dart_test.yaml` and
`analysis_options.yaml` out of the archive.

| | `4b37b72` (before the cleanup) | `6c940cf` (baseline) | `a7eed82` (end) |
|---|---|---|---|
| Tracked files | 1,634 | 1,002 | 786 |
| Lines in tracked text files | 415,007 | 302,376 | 283,902 |
| Dart lines in the packages' `lib/` | 38,598 | 26,345 | 20,629 |
| Archives: core, audio, text, vision | not measured | 62, 33, 203, 509 KB | 44, 31, 32, 304 KB |

pub.dev received 411 KB instead of 807 KB (-49%), and the packages' `lib/`
Dart shrank by 21.7%. No test was lost: every removed test moved first, except
two that tested settings the pass removed, and all 134 coverage cells stayed.

The items: (1) merged vision's four FFI binding files; (2) rewrote
`third_party/README.md`; (3) replaced the two shipped example apps after
porting their tests; (4) kept maintainer files out with `.pubignore`; (5)
removed small dead code; (6) folded `example_embedding` and
`example_segmenter` into the gallery; (7) deleted the tooling for removed
runtimes; (8) replaced the consumer harnesses with one per family; (9)
migrated or dropped the CI jobs for removed runtimes; (10) removed the
"official runtime" flags; (11) removed the hook's retired settings; (12)
regenerated stale derived data; (13) dropped five vendored headers that fed
nothing; (14) removed vision's unused `archive` and test-only `crypto`
dependencies; (15) merged the two gallery preparers; (16) removed dead gallery
code; (17) re-tested 1.0.x workarounds against 1.1.0; (18) moved shared
structs and boilerplate into core; (19) kept the testing hooks in the public
API, with reasons.

## Earlier IDs

Numbers 20 to 25 are this file's October 9 items. A is the October 8 audit at
`5228749`, and C the one at `3cf49f3` (neither is committed).

| Here | Earlier |
|---|---|
| B1 | October 9 status, point 4 |
| B2 | October 9 status, point 5 |
| B3 | 22; A5; C7 |
| B4 | 21; 24 (README); A5 (API parity); C13; C21 |
| B5 | October 9 status, point 6 |
| B6 | October 9 status, point 1; C14 (job names) |
| S1 | 20; A2; A3 |
| S2 | 23; A5 (`meta`); A6 |
| S3 | 24 (`reference_wheels.dart`); A1 (connections) |
| R2 | 25 (CI); A7; C20 |
| R3 | C5 |
| R4 | A4; A8; C6; C12; C23 |
| R5 | C1; C4; C8; C9; C11 |
| R6 | 25 (Makefile); A7 (Makefile); C2; C3; C15; C17; C18 |
| R7 | 24 (`PER_FAMILY_RUNTIMES.md`); C10; C14; C16; C22 |
| R8 | 25 (fixture); A1 |
| R9 | 23 (Hungry Fish); C19 |

S4, S5 and R10 to R15 are new on October 12.

## Re-measuring

```sh
# Repository totals at a commit (-I skips binary files)
git ls-tree -r --name-only <commit> | wc -l
git grep -I -c '' <commit> -- . | awk -F: '{s+=$NF} END {print s}'

# Dart in the packages' lib/
git grep -I -c '' <commit> -- 'packages/*/lib/*.dart' | awk -F: '{s+=$NF} END {print s}'

# What pub.dev would receive: dry runs on clean copies, never --force.
python3 -B packages/mediapipe-core/tool/publish_check.py
```
