# Debloat plan before the 0.1.0 pub.dev release

## Status on October 9, 2026

**Done and merged.** Items 1 to 18 are done, and item 19 was considered and
kept. The pass was squashed with the per-family hosting work into `3ece0dc`
and merged to `main` as `7517e9a` (#77, October 7): 18 checks passed and the
3 deploy checks were skipped. `chore/debloat` is deleted. Everything from
[Overview](#overview) down is the record of that pass, and none of it needs
doing again. Checked at `f52b6cb` (`main` on October 9), nothing it removed
has come back: vision has one ffigen config and one generated bindings file,
no "official runtime" flag exists, core still vendors the same 31 headers,
and both new packages copied item 4's `.pubignore` (models, `tool/`, `test/`,
`dart_test.yaml` and `analysis_options.yaml` stay out of the archive). Line
numbers in this section are at `f52b6cb`.

**The release grew from four packages to six.** Five pull requests have
merged since: the Exclude and Lasso brushes (#78), Decision Maker on desktop
and the web with Hungry Fish (#79), a Segment page fix (#80), Universal
Embedder and Semantic Retriever (#81), and Decision Maker on Android and iOS
(#82). They add `mediapipe_decision` and `mediapipe_retrieval`, both at
`version: 0.1.0` with `publish_to: none` like the other four. Both names are
free on pub.dev (checked on October 9). `mediapipe_core` and `mediapipe_text`
are still Google's 0.0.1 previews there.

| | `a7eed82` (end of the pass) | `7517e9a` (#77 merged) | `f52b6cb` (now) |
|---|---|---|---|
| Tracked files | 786 | 787 | 873 |
| Lines in tracked text files | 283,902 | 284,254 | 309,245 |
| Dart lines in the packages' `lib/` | 20,629 | 20,675 | 24,628 |
| Archives: core, audio, text, vision | 44, 31, 32, 304 KB | not measured | 46, 31, 31, 305 KB |
| Archives: decision, retrieval | | | 19, 23 KB |

- **The growth since the merge is new features:** +86 files and +24,991
  lines. The two new packages are 69 files
  and 17,603 lines, and one Retrieval fixture accounts for 10,468 of those
  (item 25). The gallery grew by 4,739 lines (Hungry Fish and the Decision and
  Retrieval pages), vision by 1,220 (mostly the brushes' segmenter fixture),
  CI by 534 and core by 295.
- **The line count mostly measures fixture layout.** JSON is 171,907 of the
  309,245 lines (56%; it was 159,143 of 284,254 at the merge). Nearly all of
  it is test fixtures written one number per line, and vision's landmark,
  image and GPU references alone are 117,739 lines. Files, bytes and Dart
  lines say more about the code.
- **Archives** come from `publish_check.py` with Decision and Retrieval added
  to its list (item 21). All six packages validate with zero warnings, and
  together they send pub.dev 455 KB.

### Open before publishing

In this order. Items 20 to 25 follow this list.

1. **Main's ruleset.** It still requires the six checks for jobs this pass
   removed (item 9; checked with `gh api` on October 9). Those checks never
   report, so every merge needs the admin bypass. The same edit could also
   require the Decision and Retrieval jobs, which no rule requires yet. It
   could also cover renaming the jobs still called "official Android SDK" and
   "official iOS SDK" (`debloat-candidates.md` item 14), since rules name
   checks exactly.
2. **Publishing tooling for six packages** (item 21). `publish_check.py` and
   `CONTRIBUTING.md` still name four packages, and Decision and Retrieval have
   no example.
3. **Public API to settle while it is still free to change** (item 22): the
   two constants each new family exports, and whether core 0.1.0 publishes
   `WheelRuntime`, `wheelRuntimes` and `bundleWheelRuntime` for one target.
4. **Pins: your decision.** A parallel session found this on October 9 by
   hashing and scanning both of Google's zips (not re-verified here).
   Vision, text and audio still pin Google's October 5 Android (arm64, arm,
   x64) and iOS builds: 12 pins, all in `family_runtimes.dart`. Google's
   October 8 rebuilds of exactly those files add its Clearcut usage-logging
   uploader (`play.googleapis.com/log`), so re-pinning would enable Google's
   telemetry on phones. Retrieval's October 8 phone pins already include the
   uploader, and Decision has no logger at all. The macOS and Linux files are
   byte-identical, and the Windows files differ only in PE timestamps, so
   nothing else needs re-pinning. Whichever you choose,
   `doc/privacy_and_licenses.md` should describe it.
5. **Notices.** This question was open under [Looks dead, keep](#looks-dead-keep)
   and now covers more families. Only vision ships Google's
   `third_party/NOTICE`. Text, audio, Decision and Retrieval also bundle
   Google's libraries, and they ship none. Two docs also disagree:
   `doc/privacy_and_licenses.md` ("Licenses") says the downloaded archives
   carry Google's `LICENSE` and `NOTICE`, while `PER_FAMILY_RUNTIMES.md`
   ("Before merging", Notices) says Google's delivery has neither.
6. **Devices** (see [Verification](#verification)). The iPhone was last run
   on `6c940cf`, and Test Lab has not run since #78. Decision and Retrieval
   have never run on a physical phone: Test Lab's task list has neither, and
   their CI uses the x86_64 emulator and the iOS Simulator.
7. **Then publish,** as `CONTRIBUTING.md` describes: remove `publish_to: none`
   and the `(unreleased)` marks in one commit, run `publish_check.py` and
   `test_bundled_models.py`, publish `mediapipe_core`, switch the five
   families from `path:` to `mediapipe_core: ^0.1.0`, then publish them.

Items 20, 23, 24 and 25 and the [follow-up audits](#the-two-follow-up-audits)
do not block publishing.

### 20. Shipped duplication in the new families

**Found by: Claude (October 9). Ships to pub.dev.** Retrieval was built from
Decision's skeleton, so it also copied Decision's copies of older patterns:

| What | Copies at `f52b6cb` | Size |
|---|---|---|
| Worker isolate lifecycle (`bloat-audit.md` item 2) | Five: text, vision (two), Decision and Retrieval. Once the family names are swapped, Retrieval's `lib/src/io/native_runner.dart` (161 lines) differs from Decision's (157) in about a dozen lines. | 157 to 223 lines each |
| FFI status helper and C-string helper (`bloat-audit.md` item 3) | Seven and six: Retrieval's `_string` and `_check` (`native_retrieval.dart:441-458`) repeat Decision's (`native_decision_maker.dart:246-269`). | About 20 lines per pair |
| `"$os/$arch"` target string | `native_retrieval.dart:14`, `native_decision_maker.dart:13`, `classic_text_runtime.dart:14`. Core's `platform_io.dart:69` already computes it for `TaskPlatform`. | 2 lines each |
| WebGPU adapter probe | `_webGpuAdapter` in `mediapipe_decision_web.dart:29-54` and `mediapipe_retrieval_web.dart:29-54` (once the names are swapped, the two plugins, 74 and 76 lines, differ in about ten lines), plus `webGpuAdapterPrefix`, `_softwareAdapter` and `_hardwareWebGpu` in both `capabilities.dart` files (`:51`, `:20`). | About 40 lines per copy |
| `MpEmbedding` and `MpEmbeddingResult` | Hand-written identically in text's `embedding_gemma_bindings.dart` and in `retrieval_bindings.dart`. Item 18 moved this kind of shared struct to core's `native_structs.dart`. | 20 lines |

**Fix:** move the two structs, the two helpers and the target string to core,
as item 18 did with the shared structs. Move the WebGPU probe to core's web
side, which already owns the `taskPlatformGpuReader` that both plugins set.
The shared worker is still `bloat-audit.md` item 2's larger job, which would
now have five users. Leaving the worker aside, this removes roughly 150 lines
of shipped code (an estimate: about 90 for the helpers across all families,
40 for the probe, 20 for the structs).

### 21. Publishing gaps for Decision and Retrieval

**Found by: Claude (October 9); parts are in `bloat-audit.md` item 5 and
`debloat-candidates.md` item 13. Affects what pub.dev receives.**

- `packages/mediapipe-core/tool/publish_check.py:22` (`FAMILY`) lists four
  packages and prepares only those. The dry run therefore skips Decision and
  Retrieval, and it fails if you name them. With both added, all six validate
  (see the table above).
- `CONTRIBUTING.md:42-44` says the first release is four packages "published
  together", and `:52` explains which names are free. Add the two families.
  Both names are free.
- Neither package has an `example/example.dart`, which the other four have
  had since item 3. pub.dev's score checks for one, and the package page shows
  it.
- Decision has no `tool/api_parity` snapshot, so nothing compares its native
  and web APIs. Retrieval has one.
- The offline mirror still misses Decision's and Retrieval's models
  (`tool/model_pins.py:11-15` reads three registries) and Decision's Windows
  wheel (`tool/runtime_inventory.dart` reads only `familyRuntimes`). Their
  libraries are in `familyRuntimes` now, so the rest of
  `debloat-candidates.md` item 13's mirror gap was closed by #81 and #82.
  `gallery/tool/test_desktop.py:72` still checks only three families' bundled
  libraries.

### 22. Public API added since the merge

**Found by: Claude (October 9); Decision's part is in `bloat-audit.md` item 5.
Ships to pub.dev, and removing any of it after 0.1.0 is a breaking change.**

- `mediapipe_decision.dart:18,21` exports `decisionRuntimeVersion` and
  `webGpuAdapterPrefix`, and Retrieval copied this
  (`mediapipe_retrieval.dart:23,26`, recorded in its API snapshot). Only the
  package itself uses them, the web plugins reach the prefix through
  `platform_interface.dart`, and no older family exports a runtime version.
  Either drop them from the public libraries, or keep them on purpose and
  export the same constants from every family.
- Core's public `native_assets.dart` exports all of `family_runtimes.dart`.
  Since #79 that includes `WheelRuntime`, `wheelRuntimes` and
  `bundleWheelRuntime`, about 110 lines. Since #82 they serve one target,
  Decision on Windows, which extracts Google's 61 MB library from the 1.1.0
  Windows wheel. Their TODO says to retire them once Google builds that
  library, and once they are published, retiring them breaks core's API. The
  other option is to withdraw Decision on Windows until Google's library
  arrives. That is a product decision, not a cleanup.

### 23. Small dead code

**Found by: Claude (October 9); the last three are still open from the
October 8 audits.**

- `bundleWheelRuntime`'s macOS step (`family_runtimes.dart:445`) is
  unreachable since #82. `wheelRuntimes` pins only `windows/x64`, and the
  Decision hook sends `macos/arm64` to `familyRuntimes`.
- Decision declares `meta` but never imports it (`bloat-audit.md` item 5).
- `runningInIosSimulator` is exported through `platform_interface.dart:8`,
  but its only caller is `platform_io.dart:72` (`bloat-audit.md` item 6).
- Hungry Fish: nothing reads the `FishGame.waiting` getter
  (`fish_game.dart:548`) or the `_SeaPainter.colors` field
  (`fish_game_page.dart:523`) (`debloat-candidates.md` item 19).

### 24. Stale text

**Found by: Claude (October 9). One file ships.**

- `packages/mediapipe-core/tool/PER_FAMILY_RUNTIMES.md:3` still says "Status
  on 2026-10-07: on `chore/debloat`", and its "Before merging" section (`:124`)
  lists what was left before a merge that has already happened. Step 4 below
  pointed there. Retitle it for the release and keep its open entries: the
  iPhone, release builds with an App Store validation of the iOS frameworks,
  and notices.
- The "Where it runs" table at `README.md:119` has no Decision or Retrieval
  row, yet the text below it says every cell is tested in CI
  (`debloat-candidates.md` item 21, which now covers two families).
- `packages/mediapipe-core/lib/src/native_assets/reference_wheels.dart:8`
  ships and says the references come from the 1.1.0 release candidate "until
  1.1.0 itself is published". Google published 1.1.0 on October 6, and the
  Decision and Retrieval references already use it. Either move the older
  families' references to the final wheel or reword the comment.

### 25. Generated data and CI repeats

**Found by: Claude (October 9). Not shipped.**

- `packages/mediapipe-task-retrieval/test/fixtures/embedding_gemma_2_text_vision_reference.json`
  is 10,468 lines: 13 embeddings of 768 numbers each, one number per line. It
  is written by `tool/generate_reference.py:164` with
  `json.dumps(reference, indent=1)`, and Decision's generator does the same
  (`:106`). Writing each vector on one line keeps the same data and removes
  about 10,000 lines. `bloat-audit.md` item 1 proposes the same for the
  gallery's reference tables (about 4,700 lines). Vision's JSON fixtures use
  the same layout and could follow if the line count matters.
- `retrieval.yaml` copied both of `decision.yaml`'s repeats
  (`bloat-audit.md` item 7). It runs `dart analyze --fatal-infos` on three
  OSes (`retrieval.yaml:65`, `decision.yaml:66`), although `make analyze` in
  `main.yaml` already covers both packages. Its web job also runs on
  `ubuntu-24.04` (`:136`, `:250`), and hosted Linux has no hardware WebGPU, so
  that run can only check the refusal. `web.yaml`'s Chromium journey on Linux
  already checks the same refusal, because its web build includes all three
  new tasks.
- `make test_decision` and `make test_retrieval` (`Makefile:163`, `:172`) have
  no caller.

### The two follow-up audits

`bloat-audit.md` (8 items, at `5228749`) and `debloat-candidates.md` (23
items, at `3cf49f3`) were written on October 8, after this pass and before
#81 and #82. All eight audit items and eight of the 23 candidates (13, 14,
16, 17, 19, 21, 22 and 23) were spot-checked at `f52b6cb`. All are still open
except the first point of candidates item 22: UP-049 now has its row in the
Current issues table. Two have grown: the error card is now in five gallery
pages instead of three (audit item 8: audio, text, Decision, Hungry Fish and
Retrieval), and `GalleryTask.downloadsModel` is set on four tasks
(candidates item 23). Items 20 to 25 add only what those audits could not
see or what has grown since. The rest of their items stand as written.

## Overview

**Goal:** publish `mediapipe_core`, `mediapipe_vision`, `mediapipe_text` and
`mediapipe_audio` 0.1.0 to pub.dev in the next 2 to 3 weeks, with the repository
and the published packages as lean as they can be. That means deleting dead
code, removing duplicated code and duplicated generated output, clearing out
what the switch to Google's per-family libraries left behind, and making sure
nothing reaches pub.dev that a consumer does not need. (`mediapipe_decision`
and `mediapipe_retrieval` were added after this pass; see
[Status](#status-on-october-9-2026).)

**Ground rule:** test coverage stays the same. Anything that removes a test moves
it somewhere else first.

**Result (October 7, 2026):** every item is done on `chore/debloat`, except
19 (kept, with the reasons there) and the [Looks dead, keep](#looks-dead-keep)
list. Steps 1 to 5 and items 6 and 15 are one commit, `02b80a3` (pushed);
items 17 and 18, and the benchmark case item 12 had left open, are the nine
commits after it, up to `a7eed82`. All of it merged as `7517e9a` (#77).

| | `4b37b72` (before the cleanup) | `6c940cf` (this plan's baseline) | `a7eed82` |
|---|---|---|---|
| Tracked files | 1,634 | 1,002 | 786 |
| Lines in tracked text files | 415,007 | 302,376 | 283,902 |
| Dart lines in the packages' `lib/` | 38,598 | 26,345 | 20,629 |
| Archives: core, audio, text, vision | not measured | 62, 33, 203, 509 KB | 44, 31, 32, 304 KB |

- **This branch:** -216 files (-21.6%) and -18,474 lines (-6.1%); the
  packages' `lib/` Dart is 5,716 lines (21.7%) smaller, and pub.dev receives
  411 KB instead of 807 KB (-49%).
- **Since before the cleanup:** -848 files (-51.9%) and -131,105 lines
  (-31.6%).
- **Tests:** none lost. The two vision tests that went (the hook's "retired
  iOS/Android opt-out names the fix" checks) tested settings item 11 removed;
  every other removed test moved first, and all 134 coverage cells CI records
  are unchanged. What ran is under [Verification](#verification).

**Measured at:** `exp/split-runtimes` at `6c940cf` (2026-10-07), the commit that
moved every native platform to Google's per-family 1.1.0 libraries. That commit
says the CI workflows and consumer-app tools were deliberately left unmigrated
until Google publishes download URLs, and no CI had run on it then (the
workflows trigger only on pull requests and pushes to `main`). Line numbers
from here down are at `6c940cf` unless an item says otherwise.

**Where things stood at `6c940cf`:**

- Since `4b37b72` (before the cleanup PRs #71, #75, #76 and the runtime switch),
  the repo went from 1,634 files and 415,007 lines to **1,002 files and 302,376
  lines: -632 files (-38.7%) and -112,631 lines (-27.1%)**. Lines here and
  below are `git grep -c ''` over tracked text files at each commit.
- Published archives at `6c940cf`, from `flutter pub publish --dry-run` on a
  clean export (nothing uploaded):

  | Package | Compressed | Largest parts, uncompressed |
  |---|---|---|
  | mediapipe_core | 62 KB | `native/` headers 129 KB (more than `lib/` at 99 KB) |
  | mediapipe_audio | 33 KB | `lib/` 63 KB |
  | mediapipe_text | 203 KB | `example/` app 249 KB, `lib/` 83 KB |
  | mediapipe_vision | 509 KB | `third_party/` notices 1,054 KB, `lib/` 369 KB, `example/` app 312 KB |

- What is left falls into four groups: leftovers from the runtime switch (the
  biggest), files that ship but should not, duplication, and a small amount of
  dead code.

**How this report was made:** two independent read-only analyses with the same
brief, merged here.

- **Claude:** a resolved-AST reference scan (analyzer 14.5, 380 Dart files,
  6,391 declarations, including conditional imports, super parameters,
  assignments and pattern fields), clone detection across every code file,
  native method-channel and JS message checks, tracing of every script,
  Makefile target, CI step and doc link, regeneration of derived files in a
  scratch copy, and publish dry-runs.
- **Codex** (gpt-6.1-sol, read-only sandbox, no network): static review of
  the committed tree.
- Shared findings are merged and credited to **Both**. Anything only Codex
  found was re-verified by Claude before inclusion; two Codex findings did not
  hold up and are listed under [Disputed](#disputed-and-excluded) instead.

**Summary of the work:**

| # | Item | Ships? | Size | Confidence | Found by | Step |
|---|---|---|---|---|---|---|
| 1 | Merge vision's four FFI binding files, move under `lib/src` | Yes | ~830 to 855 duplicate lines, 2 configs | Confirmed | Both | 2 |
| 2 | Rewrite the stale `third_party/README.md` | Yes | 56 lines | Confirmed | Both | 2 |
| 3 | Replace the two shipped example apps (port their tests first) | Yes | 117 files, ~7.3k lines | Confirmed | Both | 3 |
| 4 | `.pubignore` maintainer-only files | Yes | 48 files, ~4.2k lines | Confirmed | Both | 2 |
| 5 | Small dead code | Mixed | ~100 lines | Confirmed | Both | 1 |
| 6 | Fold `example_embedding` and `example_segmenter` into the gallery | No | 78 files, ~7.3k lines | Confirmed | Both | 6 |
| 7 | Delete the build and packaging tooling for removed runtimes | No | 9 files, 1,897 lines + CI/Makefile | Confirmed | Both | 1 |
| 8 | Replace the consumer test harnesses with one per-family harness | No | ~2,500 lines to rewrite | Confirmed | Both | 4 |
| 9 | Migrate or drop the CI jobs and Makefile targets for removed runtimes | No | 9 jobs, ~520 workflow lines | Confirmed | Both | 1 and 4 |
| 10 | Remove the macOS/iOS "official runtime" capability flags, package and gallery | Yes | ~200 lines | Confirmed | Both | 2 |
| 11 | Remove the hook's handling of retired settings | Yes | ~20 lines | Confirmed | Claude | 2 |
| 12 | Regenerate stale derived data (gallery reference tables, benchmark golden) | No | 2 data sets | Confirmed | Codex, verified | 1 |
| 13 | Core ships 36 vendored C headers; 5 of them feed nothing | Yes | 129 KB; 541 dead lines | Confirmed | Both | 2 |
| 14 | Vision's unused `archive` and test-only `crypto` dependencies | Yes | 2 dependencies | Confirmed | Both | 2 |
| 15 | Merge the two gallery preparers | No | ~870 lines, one of two | Confirmed | Claude | 6 |
| 16 | Dead gallery code | No | ~40 lines | Confirmed | Claude | 1 |
| 17 | Re-test 1.0.x workarounds and upstream notes against 1.1.0 | Mixed | Unknown | Judgment | Claude | 6 |
| 18 | Smaller duplication (bindings structs, task boilerplate, model pins) | Mixed | Tens to hundreds of lines | Judgment | Both | 6 |
| 19 | Testing hooks in the public API | Yes | 4 members | Judgment | Codex, verified | 2 |

---

## Status of the original items 1 to 6

### 1. Merge vision's four FFI binding files

**Still applies. Found by: Both.** **Done in step 2:** one ffigen config
(`ffigen.yaml`) now generates `lib/src/third_party/mediapipe/vision_bindings.dart`
(2,646 lines, the same 65 functions and 69 types as the three old files' 3,699
lines). The segmenter's hand-written file keeps only its own API (169 to 82
lines) and embeds the generated `MpBaseOptions`, whose layout the ABI test now
checks against Google's ctypes. The face and segmenter wrappers use the shared
base-options, create, error and mask helpers. Vision's suites give the same
per-test results as before the change.

The four files under `packages/mediapipe-task-vision/lib/third_party/mediapipe/`
(3,868 lines) all bind `package:mediapipe_vision/mediapipe.dylib`:

| File | Lines | Source | Used by |
|---|---|---|---|
| `mediapipe_vision_bindings.dart` | 628 | `ffigen.yaml` (face detector) | `native_face_detector.dart` |
| `face_landmarker_bindings.dart` | 784 | `ffigen_face_landmarker.yaml` | `native_face_landmarker.dart` |
| `vision_tasks_bindings.dart` | 2,287 | `ffigen_vision.yaml` (8 tasks) | all other `native_*.dart` |
| `interactive_segmenter_bindings.dart` | 169 | Hand-written from the Python ctypes definitions (no published C header) | `native_interactive_segmenter.dart` |

- 20 to 21 types (`MpBaseOptions`, `MpCategory`, `MpRect`, `MpImageInternal` and
  others) are defined 2 to 4 times: **828 to 855 redundant lines**, depending on
  how declarations are counted (Claude 828, Codex 855).
- Three private `_checked` helpers repeat the shared one:
  `native_face_detector.dart:159`, `native_face_landmarker.dart:181` (identical),
  and `native_interactive_segmenter.dart:201` (takes an `int` status). The
  shared `checkVisionCall` (`native_vision_task.dart:126`) already delegates to
  `checkedCall` (`native_vision_image.dart:160`), so only the three private
  copies remain (correction by Codex).
- The bindings sit in `lib/third_party/`, so they are public library paths.
  Text and audio keep theirs under `lib/src/`.

**Plan:** add `face_detector.h` and `face_landmarker.h` to `ffigen_vision.yaml`
and regenerate; delete `ffigen.yaml`, `ffigen_face_landmarker.yaml` and the two
face binding files; update `Makefile:67-70`; make the segmenter's hand-written
file import the shared structs (the reference tests already check ABI sizes and
offsets); point the face and segmenter wrappers at `checkVisionCall`; move the
bindings to `lib/src/third_party/mediapipe/`.

**Done when:** one generated file plus the hand-written segmenter file, no
struct defined twice, one error helper, vision unit and ABI tests and the
gallery's macOS CPU/GPU suites pass.

### 2. Rewrite the stale `third_party/README.md`

**Still applies. Found by: Both.** Ships to pub.dev. **Done in step 2.**

`packages/mediapipe-task-vision/third_party/README.md` still describes Bazel
source builds of `libface_detector.dylib` and `libface_landmarker.dylib`
(lines 6-8), says each task has its own dylib (line 38), describes Objective-C
class prefixing between two dylibs (lines 30-42), cites
`tool/build_native.py`, and names the 1.0.0 wheel as the reference oracle
(lines 48-53). All of that contradicts `family_runtimes.dart` and
`reference_wheels.dart`. Rewrite it around the per-family pins, the header
provenance and the notice provenance, and keep the license-source attribution.

### 3. Replace the two shipped example apps

**Changed. Found by: Both; corrections by Codex.** Ships to pub.dev.
**Done in step 3 (`02b80a3`):** both apps are now one `example/example.dart`
each; the text archive went from 203 KB to 32 KB and vision's from 509 KB to
305 KB. The classic text models moved to the text package's `models/`. The
gallery's controller tests gained the two camera checks the vision app had
that the gallery lacked (denied camera, page opens idle).

| App | Files | Lines | Platforms | CI |
|---|---|---|---|---|
| `packages/mediapipe-task-text/example` | 41 | 3,113 | macOS | `main.yaml:133` (integration test), plus `make test_only` |
| `packages/mediapipe-task-vision/example` | 76 | 4,243 | iOS, macOS | Runs through `make test_only` (`test_examples`) and `make build_vision_camera` in `main.yaml`'s `native-tasks` job |

Corrections to the earlier version of this plan:

- **Vision's example has tests to port.**
  `vision/example/test/face_camera_controller_test.dart` (224 lines) covers frame
  delivery to live-stream inference with dropped frames, initialization
  cancellation, permission denial and an idle start. Compare it with
  `gallery/test/live_camera_controller_test.dart` and port what the gallery
  lacks. (Found by Codex.)
- **Vision's example is in CI**, through `make test_only`. The earlier plan
  said it was not.
- Text's example test checks the exact BERT score, Spanish detection and USE
  reload after an option change (`text_tasks_test.dart:30,44,58`); the gallery's
  `text_tasks_test.dart:21` is simpler. Port those checks.

**Plan:** port the tests above; replace both apps with a single Dart example
file each (core and audio already ship `example/example.dart`); point the
READMEs at the gallery; switch `vision/tool/IOS_SIMULATOR.md` users to the
gallery (that doc is retired anyway, see item 7); delete
`vision/tool/prepare_face_example.py` (23 lines); update `Makefile` lines 3, 31,
126-136, 150-154, 166-167 and the `main.yaml:133` step.

**Done when:** the text archive is about a third of its 203 KB, the vision
archive has no app scaffolding, and every ported assertion passes.

### 4. `.pubignore` maintainer-only files

**Changed and extended. Found by: Both.** Ships to pub.dev. **Done in step 2
(`02b80a3`).**

| Package | Exclude from the archive (keep in the repo) | Files / lines |
|---|---|---|
| core | `native/` (36 vendored headers and README; see item 13) | 37 / 3,675 |
| audio | `native/audio_stream_bridge_test.c`, `dart_test.yaml` | 2 / 207 |
| text | `native/text_stream_bridge_test.c` | 1 / 118 |
| vision | `ffigen.yaml`, `ffigen_face_landmarker.yaml`, `ffigen_vision.yaml`, `dart_test.yaml` | 4 / 152 |
| all four | `analysis_options.yaml` (it includes `../analysis_options.yaml`, which is not published) | 4 / 22 |

Audio's `dart_test.yaml` now sets `concurrency: 1`, which the repo's own test
run needs: exclude it from the archive, do not delete it (Codex). The family
hooks compile only `audio_stream_bridge.c` and `text_stream_bridge.c`, so the
bridge `.c` and `.h` files must stay in the archive.

### 5. Small dead code

**Changed. Found by: Both.**

| What | Where | Ships | Evidence |
|---|---|---|---|
| `hasFamilyRuntime` | `core/lib/src/native_assets/family_runtimes.dart:176-177` | Yes, exported by `core/lib/native_assets.dart` | No caller anywhere; hooks use `requireFamilyRuntime`. The earlier plan wrongly said it does not ship (Codex). |
| `TaskCapabilities.macosCpu` | `core/lib/src/capabilities/task_capabilities.dart:163-174` | Yes | Only `core/test/capabilities_test.dart:5` calls it; it describes "the shared 1.0.1 distribution". Move the test to `cpuOnTargets` and delete it. |
| `cpuOnTargets` default `runtimeVersion = '1.0.1'` | `task_capabilities.dart:148` | Yes | Every family passes `runtimeVersion` explicitly; the default is stale. Make it required. |
| `VisionTaskWorker.name` | `vision/lib/src/io/vision_task_worker.dart:35` | Yes | Internal getter with no reference (analyzer scan). |
| `tool/check_docs.py` | repo tool | No | Not dead: `CONTRIBUTING.md:30` documents it as a manual check (Codex corrected the earlier "unwired"). Optionally add it to CI. |
| Fixture READMEs | `vision/test/fixtures/{image_tasks,segmenter_tasks,landmark_tasks,object_detection}/` | No | No README names their generator scripts; add one each. |

**Done in step 1:** all four removals above, the API snapshots updated to
match, and the four fixture READMEs. The generators are not orphans after all:
`tool/cpu_reference.py` runs each one by building its file name
(`generate_{task}_reference.py`), which name searches cannot see.

### 6. Fold `example_embedding` and `example_segmenter` into the gallery

**Still applies. Found by: Both.** **Done in step 6.** Both apps are gone
(78 tracked files, 3.1 GB of local build output). The three generative text
test files moved to `packages/mediapipe-task-text/test/`, tagged
`modern-text` (35 tests, unchanged; the classic-only Linux and Windows run
excludes the tag and `tool/test_modern_text.py` runs it). The example's reason
for living apart ("without loading the incompatible inherited text runtime")
ended with the per-family libraries: classic and generative tasks pass in one
`dart test` run (96 tests). The segmenter's controller tests moved to
`gallery/test/segment_editor_controller_test.dart` against the gallery's
controller (8 tests: the letterboxing test went with the example-only
geometry it tested, and one test of the gallery's tap ring was added); the
gallery journey now draws, undoes and clears on the Segment page, and the
macOS gallery job prepares Interactive Segmenter. The demo UI test of
`example_embedding` was not ported: everything it asserted through widgets
is compared with Google's references by the moved tests and the fresh macOS
consumer. CI: `segmenter-consumer` is gone, its coverage row comes from
`native-tasks`; `embedding-consumer` records its row from
`test_embedding_macos.py`. The 134 recorded coverage cells are unchanged.
**Main's ruleset must also drop "MagicTouch / fresh macOS consumer".**

`example_embedding` (41 files, 4,279 lines) and `example_segmenter` (37 files,
3,052 lines) are excluded from publishing but run in CI (`main.yaml:118`,
`main.yaml:416`). Their tests hold real coverage: the three modern text test
files alone are 982 lines (ABI, streaming ownership, cancellation, errors); move
those into `packages/mediapipe-task-text/test/`, and the UI tests into the
gallery (Codex). `gallery/lib/segment/editor_controller.dart` repeats 144 lines
of `example_segmenter/lib/editor_controller.dart`, and the two
`mask_overlay.dart` files are identical; both duplicates go away with this item
(Claude).

---

## New findings

### 7. Delete the build and packaging tooling for removed runtimes

**Confirmed. Found by: Both (Codex CX-01, CX-02).** Not published.
**Done in step 1**, with the five consumer scripts that only worked with these
tools (listed below the table).

`6c940cf` removed the source-built face runtimes, the macOS engine archive, the
wheel-extracted runtimes and the iOS-only Interactive Segmenter. The vision hook
now only calls `bundleFamilyRuntime` (`vision/hook/build.dart:54`). These tools
build or package runtimes that nothing consumes any more:

| File (under `packages/mediapipe-task-vision/tool/`) | Lines | What it did |
|---|---|---|
| `build_native.py` | 323 | Bazel source build of the macOS face runtime (1.0.0) |
| `build_android.py` | 230 | Bazel source build of a combined Android runtime |
| `build_ios_simulator.py` | 142 | Cross-build of the combined iOS simulator runtime |
| `prepare_native_release.py` | 157 | Packaged a source build for the old public release |
| `prepare_macos_tasks_runtime.py` | 218 | Packaged the macOS engine archive from the 1.0.0 wheel; its `from cpu_reference import MACOS_WHEEL` no longer resolves |
| `prepare_interactive_segmenter.py` | 385 | Extracted the 1.0.1 segmenter runtime from wheels |
| `macho_metadata.py` | 147 | Install-name rewriting for the above; core's `family_runtimes.dart` now does this for Google's files |
| `RELEASING.md` | 153 | Marked "**Retired.** ... The steps stay for history." |
| `IOS_SIMULATOR.md` | 142 | Marked "**Retired.** ... Kept for history." |
| **Total** | **1,897** | |

**Before deleting:**

- `generate_interactive_segmenter_reference.py:22` imports `PACKAGE` and
  `MODEL_SHA256` from `prepare_interactive_segmenter.py`, and
  `test_desktop.py:117` imports `MODEL_SHA256` and `MODEL_URL` from it. Move
  those constants first (Codex).
- Keep `native_smoke.cc` and `native_landmarker_smoke.cc`. Their `static_assert`
  ABI checks back the bindings (`ffigen_vision.yaml:3` relies on them for enum
  sizes), so repoint them at the vendored headers instead of the old builds
  (Codex; Claude had listed them for deletion).
- `upstream-issues.md` cites `tool/build_native.py` as where the UP-001
  workaround lives; update that pointer (see item 17).

**What step 1 did:** deleted the nine files above, plus five consumer scripts
that cannot run without them or the old releases (`mobile_consumer.py`,
`test_ios_consumer.py`, `test_android_consumer.py`, `test_prebuilt_macos.py`,
`test_segmenter_macos.py`, 913 lines) and the template only
`test_segmenter_macos.py` used (191 lines). The segmenter model pin moved to
`lib/models.dart` readers. The two smoke files became `tool/abi_check.cc`: the
same 15 `static_assert`s, compiled header-only by `make test_vision`, since
their inference halves only ever ran against the deleted builds. Doc pointers
in `upstream-issues.md` and `PER_FAMILY_RUNTIMES.md` now name `6c940cf` as
where the deleted tools live.

### 8. Replace the consumer test harnesses with one per-family harness

**Confirmed. Found by: Both (Codex CX-02, CX-04, CX-05).** Not published.
**Done in step 4 (`02b80a3`), without waiting for a URL:** every harness reads
the libraries from `MEDIAPIPE_ASSET_SOURCE`, which `consumer_packages.py`
writes into the fresh app's `asset_source` (and keeps out of the app's own
commands, so models still come from Google). Instead of one new harness, the
existing ones share four helpers in `consumer_packages.py` (`copy_package`,
`core_hook_defines`, `consumer_environment`, `family_runtime`): each still
covers something the others do not (bundled models offline, text and vision
coexisting in debug and release, every vision task against the wheel on CPU
and Metal, a release GPU app), so merging them would only move code.
`mirror_runtime_assets.py` reads the pins through the new
`tool/runtime_inventory.dart`. `test_macos_tasks_runtime.py` is now
`test_macos_references.py`. Passed locally on macOS:
`test_bundled_models.py`, `test_embedding_macos.py`, `test_flutter_macos.py`,
`test_macos_references.py`. The two `test_desktop.py` harnesses (Linux and
Windows) are migrated and lint-clean but not run.

These scripts build fresh Flutter apps against runtimes or settings that no
longer exist. Several cannot even start:

| Script | Lines | Problem at `6c940cf` |
|---|---|---|
| `text/tool/test_embedding_macos.py` | 196 | Imports `macos_engine` (gone); writes `tasks_runtime` and `prebuilt` |
| `vision/tool/test_desktop.py` | 279 | Copies the deleted `core/test/native_assets/wheel_library_test.dart` |
| `vision/tool/test_macos_tasks_runtime.py` | 130 | Writes `tasks_runtime: true` |
| `vision/tool/test_flutter_macos.py` | 69 | Fresh-app smoke test that passes no `asset_source`, so it cannot build until the libraries have a URL |
| `gallery/tool/test_desktop.py` | 91 | Requires exactly one `libmediapipe.so`/`.dll`; records "text-and-audio-share-the-vision-runtime" (lines 68-81) |
| `core/tool/test_bundled_models.py` | 234 | Line 98 still writes `tasks_runtime: true` (otherwise fine; one-line fix) |
| `core/tool/mirror_runtime_assets.py` | 133 | Reads deleted `tasks_runtime.dart` and `ios_sdk.dart` (lines 14-16, 61); keep the tool, rewrite its inventory from `familyRuntimes` |
| Templates: 6 in `vision/tool/`, 2 in `text/tool/` | 735 | Used only by the scripts above |

Step 1 already removed `test_prebuilt_macos.py`, `test_segmenter_macos.py`,
`mobile_consumer.py`, `test_ios_consumer.py` and `test_android_consumer.py`
(item 7). What remains is about 1,600 lines that must be rewritten for the per-family libraries
anyway. One harness in core that builds a fresh app per family (with
`asset_source` until URLs exist) and runs each family's suites would replace
most of them. `PER_FAMILY_RUNTIMES.md` ("Before merging: CI and tools") already
lists this migration; this item adds the scope and the broken imports.

### 9. Migrate or drop the CI jobs and Makefile targets for removed runtimes

**Confirmed. Found by: Both (Codex CX-06).** Not published.

| Workflow job | Lines | Problem |
|---|---|---|
| `main.yaml` `native-tasks` | 149-251 | Installs Bazel/CMake/Ninja (`:165`), caches and runs the source face build (`:194`, `:200`, `make native_vision`), runs `make test_vision_flutter` |
| `main.yaml` `official-runtime-pin` | 252-273 | Runs `prepare_macos_tasks_runtime.py`, whose import is broken. **Main's ruleset requires this check by its exact name** (`main.yaml:253-255`): change the ruleset in the same step, or no PR can merge (Codex). |
| `main.yaml` `official-runtime-validation` | 274-326 | `test_macos_tasks_runtime.py` with `tasks_runtime: true` |
| `main.yaml` `prebuilt-consumer` | 327-347 | `test_prebuilt_macos.py` (broken import) |
| `main.yaml` `segmenter-consumer` | 392-436 | `test_segmenter_macos.py` (broken import) |
| `main.yaml` `embedding-consumer` | 80-148 | `test_embedding_macos.py` (broken import); also runs `make test_text` (`:116`), which `native-tasks` runs again through `make test_only` |
| `android.yaml` `emulator-consumer` | 19-105 | `build_android.py`, `test_android_consumer.py`; `:148` asks for a 1.0.0 oracle |
| `ios.yaml` `simulator-consumer` | 19-97 | `build_ios_simulator.py`, `test_ios_consumer.py`; `:125-128` caches the deleted iOS SDK adapter's zip keyed on deleted `ios_sdk.dart`; `:148` asks for a 1.0.1 oracle |
| `desktop.yaml` `face-tasks` | 19-145 | `vision/tool/test_desktop.py` (copies a deleted test) |
| `android-face-testlab.yml` | 127-132 | Asserts Google's Android SDK JNI libraries (`libmediapipe_tasks_jni.so`), removed with the SDK |

Makefile targets for removed runtimes: `native_vision`, `release_vision`,
`test_vision_flutter`, `test_vision_prebuilt`, `test_segmenter_prebuilt`,
`native_vision_ios_simulator`, `native_vision_ios_device`,
`test_vision_ios_consumer`, `test_embedding_macos`, and `native_vision` inside
`ci`. The comment at `Makefile:76-77` describes the `flutter` test tag that
`6c940cf` removed.

**Split:** the source-build jobs and targets can go with item 7 now (step 1).
The consumer jobs need item 8 and a download URL (step 4).

**What step 1 did:** removed `official-runtime-pin`, `prebuilt-consumer`,
android `emulator-consumer` and ios `simulator-consumer`; removed the source
build, its cache, its toolchain install and its artifact from `native-tasks`;
removed `test_segmenter_macos.py` and its report upload from
`segmenter-consumer`; removed the dead iOS SDK cache step. None of these
recorded a coverage row, so the coverage gate keeps every cell. Job names are
unchanged. Makefile: removed `native_vision`, `release_vision`,
`test_vision_prebuilt`, `test_segmenter_prebuilt`,
`native_vision_ios_simulator`, `native_vision_ios_device` and
`test_vision_ios_consumer`, and the stale `flutter` tag comment;
`test_embedding_macos` stays for step 4. **When this reaches main, drop or
rename `official-runtime-pin` in main's ruleset at the same time.**

**What step 4 did (`02b80a3`):** the consumer jobs run the migrated
harnesses; `android.yaml` and `ios.yaml` no longer ask for 1.0.0/1.0.1 oracles
(`official_wheels.py` lost its `ORACLES`); the Test Lab APK check expects one
library per family; `gpu-reference` is gone, since `native-tasks` runs the same
face suites against the same runner's wheel (its two coverage rows moved
there); `embedding-consumer` no longer repeats `make test_text`.

**Main's ruleset must drop six required checks whose jobs are gone:**
"Official macOS landmark runtime / pin survives this runner's Xcode",
"Fresh Flutter consumer / public runtime download",
"Face tasks / fresh arm64 iOS simulator consumer",
"Face tasks / fresh x64 Android emulator consumer",
"Official GPU comparison / same macOS runner" and (item 6)
"MagicTouch / fresh macOS consumer". **All six were still required on October
9** ([Open before publishing](#open-before-publishing), point 1).

### 10. Remove the macOS/iOS "official runtime" capability flags

**Confirmed leftover; which way to unify is a judgment call. Found by: Claude
(package side), Both (gallery side, Codex CX-09).** Ships to pub.dev.
**Done in step 2,** choosing "none": every vision task now declares macOS 14+
and iOS 15+ unconditionally, as the face tasks, text and audio already did
(the hook always bundles the library there). With the flags gone, ten of the
eleven tasks share one table (`_visionTaskCapabilities`); only the stateful
Interactive Segmenter keeps its own. That also fixed the face tasks' macOS CPU
claim, which had no minimum version (a leftover of their source-built runtime)
although Google's library needs macOS 14. The gallery lost its paired wrappers,
`GalleryTask.officialMacosCapabilities`, the `officialMacosLandmarkTasks`
plumbing through three pages and nine tests, and the `macos_engine_tasks` and
`official_web_sdk` manifest fields (nothing read the second either).

In vision's `lib/src/capabilities.dart` (520 lines), every task except the two
face tasks takes `officialMacosRuntime` and `officialIosRuntime` flags (68
references), fed by `hasMacosTasksRuntime()` and `hasOfficialIosVisionRuntime()`
in `capabilities/official_runtime_io.dart` (25 lines) and `_stub.dart` (5). They
date from when face tasks had their own runtime and the others needed the macOS
engine archive. Now one vision library serves every task, yet the face tasks
claim macOS and iOS unconditionally while the other nine check whether the
library is bundled. Related leftovers in core: `macosTasksRuntimeTargets`
(exported from `platform_interface.dart:12`) and `TaskCapabilities.macosCpu`
(item 5).

The gallery mirrors this with a parallel layer: `catalog.dart:115-230` keeps
paired `_officialMacos*` wrappers for each task (about 100 lines),
`GalleryAssets.officialMacosLandmarkTasks`, a `macos_engine_tasks` manifest
field written by both preparers, `macosEngineTasks` in
`tool/gallery_builder/lib/models.dart:104-124`, and four integration tests that
pass it around. `catalog.dart:155` still says "tool/prepare.py builds every iOS
target against Google's official SDK".

**Plan:** one availability check (is the vision library bundled?) applied the
same way to all eleven tasks, or none; drop the two flags from the public
`*CapabilitiesForPlatform` functions (API change, fine before 0.1.0); delete
`official_runtime_io/stub.dart`, `macosTasksRuntimeTargets`, `macosCpu`, and
the gallery's engine-selection layer.

**Done when:** vision's capability and coverage-matrix tests report the same
supported delegates on every target, and the gallery shows the same tiles.

### 11. Remove the hook's handling of retired settings

**Confirmed. Found by: Claude.** Ships to pub.dev. **Done in step 2
(`02b80a3`)**, with `sdk_downloads.dart` renamed `vision_tasks.dart`.

`vision/hook/build.dart:33-43` and `:58-65` exist only to reject
`official_ios_sdk: false` and `official_android_sdk: false`. Those settings were
never published, and the only thing that still sets them is `mobile_consumer.py`
(item 8). Delete about 20 lines. Also rename `vision/sdk_downloads.dart`: it no
longer pins any download, only the task lists (`visionTasks`,
`visionRuntimeTasks`), and its `android/arm` comment ("no task claims it yet")
contradicts the line below it.

### 12. Regenerate stale derived data

**Confirmed. Found by: Codex (CX-07, CX-08), verified by Claude.** Not
published. **Done in step 1**; its one open Summarizer case was resolved in
`a7eed82` (below).

- **Gallery reference tables.** `gallery/integration_test/support/official_*_references.dart`
  (5,245 lines, generated by `gallery/tool/generate_sdk_references.py`) were not
  regenerated when `6c940cf` refreshed the fixtures from the 1.1.0 RC. Claude
  regenerated them in a scratch copy: 308 changed lines in the landmark table and
  1,778 in the detection table (mostly last-digit drift; Codex counted 886 of
  1,024 CPU embedding entries different). The generator still labels its output
  "mediapipe==1.0.0" (`:48,86,165`). Regenerate and derive the label from the
  fixtures.
- **Benchmark golden.** `tool/task_benchmarks/bin/main.dart:38,55` requires a
  1.0.0 golden, while `generate_reference.py:39,43` now writes the 1.1.0 RC
  version, so a regenerated golden would fail the runner's own check.
  Regenerate `fixtures/options-reference.json.gz` with the current wheel and
  make the check follow the pin; update the README's "1.0.0 engine" text.
- **Smaller stale text:** `ffigen_vision.yaml:7` mentions "published per-task
  archives" (goes with item 1). `tool/coverage/matrix.json` gives 1.0.1-era
  reasons (lines 186, 238, 416), but changing them needs a 1.1.0 retest, so
  they belong to item 17. (An earlier version of this plan also listed vision
  test comments citing `tool/test_macos_tasks_runtime.py`; that script still
  exists, so the comments are correct.)

**What step 1 did:**

- Regenerated the three gallery tables from the current fixtures; the
  generator now takes its runtime label from the fixtures. It also found a
  fourth stale copy: `gallery/integration_test/sdk_hand_landmarker_test.dart`
  kept 21 hand points from the 1.0.0 fixture by hand. The generator now emits
  a `hand` entry and the test reads it.
- Regenerated `options-reference.json.gz` with the pinned macOS wheel (same 97
  cases and 7 expected errors), made `bin/main.dart` take the runtime from
  core's `referenceWheels`, and updated the README.
- `run_macos.py --validate-only` against the per-family libraries then
  validated 85 of 86 option rows. Two findings:
  - Google's C library appends the cause to the Summarizer's over-budget
    message ("Failed to generate content. INVALID_ARGUMENT: ..."), where its
    Python API reports only the first sentence. The runner now accepts the
    expected message followed by more text.
  - The long-input Summarizer (KEYPOINTS, no budget, streamed) drifts from the
    wheel late in the summary ("Renovations begin" vs "start"), the same kind
    of drift UP-036 records for iOS. It was left failing for a decision.
    **Resolved in `a7eed82`:** it is not drift between builds. Google's own
    wheel wrote three or four different summaries for each of the four long
    key-point cases (budgets 0, 1024, 4096 and 8192) across three runs, and
    the per-family library's varied between runs too, every version alike
    for its first 98 characters. Those four now follow Google's text for 80
    characters, the text package's rule, and the report records whether
    they matched exactly; the other 93 cases still match exactly. Validation
    now checks every case before failing and lists each failure. The
    evidence, including GitHub's M1 runner, is in UP-036.

### 13. Core ships 36 vendored C headers; 5 feed nothing

**Confirmed. Found by: Both (Claude for the unused five).** Ships to pub.dev.
**Done in step 2 (`02b80a3`):** `native/` is no longer published (core's
archive went from 62 KB to 43 KB) and the five unused headers are deleted.

`core/native/include/` (36 headers, 3,675 lines, 129 KB uncompressed) is the
largest thing in core's archive. Core's hook compiles nothing, and the text and
audio bridges include only their own headers. The only reader is vision's
maintainer tool `tool/generate_bindings.dart:5`. Exclude `native/` from core's
archive (item 4).

Of those headers, five are read by nothing at all: the text classifier, text
embedder and language detector headers, `audio_classifier.h`, and
`audio/core/common.h` (541 lines). Text and audio bindings are adapted from
Google's Python ctypes instead. Delete them, or move the whole header set next
to the tool that uses it.

### 14. Vision's unused `archive` and test-only `crypto` dependencies

**Confirmed. Found by: Both (Codex CX-10).** Ships to pub.dev. **Done in step 2
(`02b80a3`).**

`vision/pubspec.yaml:33` declares `archive`; nothing in the package imports
`package:archive/`. Line 35 declares `crypto` as a runtime dependency, but all
10 imports are in `test/`. Remove `archive` and move `crypto` to
`dev_dependencies`. Core still uses both, so this trims vision's declared
surface rather than the transitive graph.

### 15. Merge the two gallery preparers

**Confirmed. Found by: Claude.** Not published. **Done in step 6:**
`gallery/tool/prepare.py` is gone; `tool/gallery_builder` prepares every
target. Its task lists now come from the vision package's
`visionRuntimeTasks` itself (imported by file path from `bin/` and `test/`),
so `androidTasks`, `macosVisionTasks` and the regex parsing in two places are
gone too. Both preparers produced identical output (pubspec without
comments, manifest, samples, references) for `ios/arm64`,
`ios-simulator/arm64`, `linux/x64`, `windows/x64` and `web`, and for the
`--tasks` and `--modern-text-reference` combinations CI uses, before the
Python one was deleted. The iOS project patching was not ported: the
checked-in project already has every setting it added. The 8 workflow steps
and `gallery/tool/test_desktop.py` call the Dart preparer.

The gallery's pubspec and assets are generated by two implementations of the
same job: `tool/gallery_builder` in Dart (Android and macOS; 333 + 164 lines,
with tests) and `gallery/tool/prepare.py` in Python (iOS, Linux, Windows and
web; 370 lines). They share about 45 lines nearly verbatim, and the per-target
task lists are kept three times: `vision/sdk_downloads.dart`,
`gallery_builder/lib/models.dart` (`androidTasks`, `macosEngineTasks`), and
`prepare.py`, which parses `sdk_downloads.dart`. With one vision library on
every target, the lists can come from one table. Keep the Dart preparer, extend
it to every target, and delete `prepare.py`; update the 7 workflow steps that
call `prepare.py`.

### 16. Dead gallery code

**Confirmed. Found by: Claude.** Not published.

- `gallery/ios/Runner/AppDelegate.swift:10-13` and `:19-42`: the `--mediapipe-benchmark`
  channel and its `deviceInfo` handler have had no Dart caller since `d9fbdd3`
  removed `ios_face_benchmark.dart`.
- `gallery/lib/text_page.dart:30,38`: `TextPage.assets` is required and never
  read.
- Parameters never set to anything but their default (analyzer scan):
  `RecentFrameTimings.capacity`, `StatusDot.color`, `ScoreBars.digits`,
  `SurfaceCard.padding`, `CountSetting.min`, `ChoiceSetting.initial`.

**What step 1 did:** reset the gallery's `AppDelegate.swift` to Flutter's
template (-28 lines) and removed `TextPage.assets`. The six parameters stay:
turning them into constants removes no code.

### 17. Re-test 1.0.x workarounds and upstream notes against 1.1.0

**Judgment. Found by: Claude.** **Done in step 6.** Re-tested on this Mac
against Google's 1.1.0 libraries and wheel: **UP-003 is fixed**, so the padded
float mask fallback, its two bindings and the generator's copy of it are gone
(`475534f`); UP-008, UP-026, UP-028 and UP-032 still fail and keep their
workarounds; UP-037 and UP-038 are unchanged. `upstream-issues.md` is split
into current issues (27, with a table of how each stands on 1.1.0) and
history (16), with no entry text dropped and every link intact (`f919adb`).
On October 9 it had 34 current entries and 17 in history: UP-046 to UP-053
were added, and UP-024 moved to history.
Found while there: the face tasks were the only ones not refusing a withdrawn
delegate through their capability query, so `native_ios_sdk.dart` went
(`47229d9`). Not re-tested, needing hardware this Mac lacks: the Linux GPU
(UP-027, 029, 030), PowerVR and Adreno phones (UP-023, 024), Windows
(UP-025); and UP-006, 009, 013, 015, 017, whose workarounds are in tests and
generators, not shipped code.

Workarounds for 1.0.x bugs may no longer be needed on the 1.1.0 libraries.
Example: `vision/lib/src/io/native_vision_task.dart:234-252` copies padded float
masks one value at a time because "the pinned 1.0.0 float accessor aborts"
(UP-003). Shipped code cites 15 `UP-` entries; retest each against 1.1.0 and
delete the workarounds that are fixed.

`upstream-issues.md` (1,087 lines, 45 entries) mixes current problems with
entries about runtimes the packages no longer use (UP-001, 002, 004, 011, 012
for source builds; UP-016, 019, 022, 033, 039 for Google's Android Java SDK;
UP-035, 036, 040 for its iOS SDK), and its "Validated baseline" section
describes 1.0.0 wheels. 17 entries are referenced from nowhere else. Since this
file is the record for Google, split it into current issues and a history
section rather than deleting entries.

### 18. Smaller duplication

**Judgment. Found by: Both.** **Done in step 6:**

- The five C structs audio and text both declared are core's
  `native_structs.dart` (`deb3eac`).
- One `runVisionRequest` helper runs every vision wrapper's IMAGE/VIDEO
  request, and Face Detector, Object Detector and Face Landmarker use the
  shared copy helpers (`c4a8b37`, -199 lines of shipped code).
- One set of gallery live adapters serves native and web (`fccc3e0`, -732
  lines), checked on macOS and in Chromium.
- Core's `tool/model_pins.py` gives the twelve generators and probes their
  model pins from the registries (`9fa6a1d`).
- Decision and Retrieval, added after this pass, repeat several of these
  patterns: see item 20.

- **Audio and text copy five C ABI structs** (`MpBaseOptions`,
  `MpClassifierOptions`, `MpCategory`, `MpClassifications`,
  `MpClassificationResult`): byte-identical in
  `audio_classifier_bindings.dart` and `classic_text_bindings.dart` /
  `embedding_gemma_bindings.dart`, 56 lines per copy (Codex CX-13, verified).
  Under "core owns the shared layer" they could live in core, now that every
  family uses the same 1.1.0 release.
- **Vision's native task wrappers** repeat 30 to 56 lines of create, detect and
  close boilerplate across ten files (`native_hand_landmarker.dart`,
  `native_gesture_recognizer.dart`, `native_pose_landmarker.dart` and others);
  face detector and face landmarker share 96 lines (Claude). A generic helper
  could absorb part of it.
- **The gallery's live task adapters** repeat one per-task class in
  `gallery/lib/live/live_tasks_native.dart` (664 lines) and
  `gallery/lib/web/live_tasks.dart` (542 lines); the clone scan found 189 and
  183-line repeated runs (Claude).
- **Model SHA-256 pins** are repeated between the public registries and
  maintainer scripts (for example `text/lib/models.dart:62` and
  `text/tool/probe_text_gpu.py:19`) (Codex CX-21, verified). A shared pin
  loader for tools would save tens of lines; keep the hashes recorded inside
  generated receipts.

### 19. Testing hooks in the public API

**Judgment. Found by: Codex (CX-20), verified by Claude.** Ships to pub.dev.
**Considered in step 2 and kept.** Moving the two members to an unexported
library would make the gallery's `audio_page_test.dart` import
`mediapipe_core` directly, which both generated gallery pubspecs would then
have to declare, and API parity requires the web `ModelStore` to keep the same
members anyway. They are already `@visibleForTesting`; the change would cost
more than the two members it hides. Since #78, a third test uses them,
`gallery/test/segment_page_test.dart:68`.

`ModelStore.debugBundledModels` and `ModelStore.debugCacheDirectory` are public
static members marked `@visibleForTesting` (`core/lib/src/model_store_io.dart:38-45`,
`model_store_web.dart:45-52`), and all four API snapshots list them. Only tests
use them (`core/test/model_bundling_test.dart`, `gallery/test/audio_page_test.dart:116`).
The web `debugCacheDirectory` documents itself as unused. Before 0.1.0 is the
cheap moment to move them to an internal testing library.

**Also judgment, found by the analyzer scan (Claude):** a few dozen public
options are never set by any test or demo, for example `displayNamesLocale` on the
audio, object detector and image classifier options, and `model:` on gesture,
pose, holistic, object detector, classifier and segmenter options. They are
Google-parity API, so keep them; they are coverage gaps, not dead code.

---

## Disputed and excluded

These came only from Codex. Claude checked them, and they are left out of the
recommendations:

- **CX-16, "private `macosGpu` parameter is always true".** False. Five call
  sites pass `macosGpu: true`, but `holisticLandmarkerCapabilitiesForPlatform`
  (`capabilities.dart:245`) omits it and relies on the `false` default. That is
  what keeps Holistic's macOS GPU withdrawn (UP-026). Removing the parameter
  would start claiming a GPU path Google's library cannot run.
- **CX-14, "share the worker request queue through core".** The 11-line block is
  real and identical in `audio/assets/worker.js:7-17` and
  `text/assets/worker.js:16-26`. But each family's worker is a separate script
  asset; sharing it means loading a second script from core's package path in
  every family worker, which adds more coupling than 11 lines are worth.
  **October 9:** there are four copies now (audio, text, Decision and
  Retrieval; vision's worker has its own queue). Each is still about 11
  lines, so the cost of sharing compared with what it saves is unchanged.

Claude's own earlier claims that turned out wrong, corrected above:

- `vision/example` is in CI (through `make test_only`), and it has a 224-line
  test suite to port (item 3).
- `hasFamilyRuntime` ships and is exported (item 5).
- `tool/check_docs.py` is documented as a manual check, not unwired (item 5).
- The earlier "keep `test_linux_gpu.sh`" example is moot: that script was
  deleted in `9383185` (#71); `GPU_VALIDATION.md:74` points to it in history.

## Looks dead, keep

| What | Why it stays |
|---|---|
| JSON reference fixtures and binary fixture inputs | Google oracle outputs and their inputs; every non-JSON fixture has a tracked reference. Excluded from pub by `.pubignore`. |
| `third_party/NOTICE`, `LICENSE`, `OPENCV_CAROTENE_NOTICES` | Required notices. Confirm with the Google contact whether the OpenCV notice still applies to Google's per-family libraries and whether core should carry the NOTICE for every family. Still open on October 9, now for five families ([Open before publishing](#open-before-publishing), point 5). |
| Text and audio stream bridges (`native/*_bridge.c`, `.h`) | Compiled by the family hooks; every exported bridge function is bound from Dart. |
| Vision's Android plugin | `gpuRenderer` has a Dart caller (`mediapipe_vision_android.dart:17`). |
| ~~`vision/lib/src/io/native_ios_sdk.dart`~~ | Removed after all in step 6 (`47229d9`): it was the face tasks' simulator GPU refusal (Codex), and the face tasks now refuse a withdrawn delegate through their capability query like every other task. |
| Browser worker `preload` and `stats` messages | Called from `vision/assets/bridge.js` and the browser tests, dynamically. |
| The `runtime.json` files (five since #79 and #81) | Same shape, different packages, files and integrity hashes. |
| Fixture generators, release and mirror tools, `check_docs.py` | Run by hand. Repair the broken ones (items 8, 12) rather than delete them. |
| `tool/abi_check.cc` (was `native_smoke.cc`, `native_landmarker_smoke.cc`) | ABI `static_assert`s behind the bindings, repointed in step 1; `make test_vision` compiles it. |
| Gallery samples, fonts, platform scaffolding | All referenced; scaffolding stays wherever its app stays. |
| Root and package `MIGRATION.md` | Google's 0.0.1 `mediapipe_core`/`mediapipe_text` are on pub.dev, so the guides have readers. |
| Skipped tests | Same-host oracle, GPU-driver, simulator and missing-library skips are still meaningful. |
| `reference_wheels.dart` in core's `lib/` | Only tests use it, but tests in all four packages import it; moving it out of the published library would need a shared test package. Small (59 lines), so leave it. |

## Verification

**After the merge (checked October 9):**

- **CI.** PR #77 ran 21 checks: 18 passed and the 3 deploy checks were
  skipped. #78 to #82 each merged with no failing check.
- **Test Lab** ran once on `main`, at `97d5baa` (#78, run 37753409212, October
  8). The Pixel 8a and the Galaxy S24 passed every test. The Galaxy A12 passed
  34 of 38, and all four failures were camera tests stopped by CameraX's "The
  camera device has encountered a recoverable error". Test Lab has not run
  since #79, and its task list includes no Decision or Retrieval task.
- **The iPhone** has not run since `6c940cf`.

Everything below ran on this Mac (M4 Max) at `92343ef` unless it says
otherwise. `a7eed82` changes only the benchmark and its notes, so the
packages, gallery and workflows these results cover are the same.

- **Static checks:** `make analyze`, `make check_format`, the gallery's
  analyzer, the gallery builder's analyzer and 21 tests, API parity (0
  findings, snapshots unchanged), the coverage gate's tests, every workflow
  parsing as YAML, and `check_docs.py` (28 Dart samples from 9 docs).
- **Package suites:** core 55; text 96 (61 classic, 35 generative) and its
  stream bridge; audio 45; vision's ABI check, 168 tests plus 107 skipped
  without same-host references, 337 plus 1 skipped with Google's CPU and
  Metal references from this Mac, and the isolated memory test.
- **Gallery:** 98 unit tests.
- **Devices,** each suite with the same counts as at `6c940cf`:
  - iOS Simulator (CPU): the 11 suites `ios.yaml` runs, plus the generative
    text suite.
  - Android emulator (API 31): `sdk_all_test` (32 pass, 1 skip), the still
    image and generative text suites in debug; `sdk_all_test` in release (38
    pass, 1 skip), with R8 keeping every plugin field.
  - Web, release build: WebKit's API suite, every comparison with Google's
    JavaScript runtime exact, and the gallery journey in WebKit and Chromium,
    56 checks across all 16 web tasks in each.
  - macOS: `main.yaml`'s three gallery suites in debug and release, on CI's
    11-task preparation. The debug journey took 5:10 once; rerun on the same
    preparation it took 0:40 (0:42 at `6c940cf`).
- **Benchmark,** with `a7eed82`'s rules: CI's command (25 iterations, 3
  reloads) passed all 97 option cases in two runs, as did a validation-only
  run. With the four long key-point cases compared exactly again, a run
  fails and lists all four.
- **Publish dry-runs** (clean export, nothing uploaded): core 44 KB, audio
  31 KB, text 32 KB, vision 304 KB. Core reports no warnings; the families'
  only error is the expected `path:` dependency on core.
- **Earlier on the branch**, at the commits that changed them: the macOS
  consumer harnesses (`test_bundled_models.py`, `test_embedding_macos.py`,
  `test_flutter_macos.py`, `test_macos_references.py`), `test_modern_text.py`,
  and the Chromium overlay and segmenter display tests.
- **CI** had not run on this branch at the time. It had run on `02b80a3`
  through the hosting branch (`a8212da`, which only adds the library
  download): Linux and Windows passed every CPU job, and so did the Android
  emulator. On macOS only the Summarizer comparisons failed, which `a7eed82`
  and the hosting branch addressed. The GPU failures on Linux and Test Lab's
  Pixel 8a, and an Android Interactive Segmenter test, were in code the
  cleanup did not change. Before #77, the hosting branch fixed the segmenter
  test and withdrew the two GPU paths (UP-046, UP-026).

**Not verified at the time:** this branch's commits after `02b80a3` on Linux,
Windows, Android phones and any Android GPU, and the iPhone (it needs your
phone; last run on `6c940cf`). CI and Test Lab have covered all of that
since, except the iPhone (see "After the merge" above, including the A12's
camera failures).

**Limits of the analysis itself:** the analyzer scan treats string-based
references (method channels, JS interop, `byName`) by name only, and pairs
conditional-import variants by name; members reachable only that way were
checked by hand. Unknown external users of the public API cannot be ruled
out; nothing is published yet, so that risk is low.

## Suggested order

**Done except step 5:** steps 1 to 4 and 6 landed in #77. Step 5 is now
[Open before publishing](#open-before-publishing), which covers six packages.

One branch, one commit per step, each step verified locally before the next
starts (CI cannot run on this branch until Google's libraries have a URL).
Nothing is pushed until the whole pass is done.

**Update, October 7:** the libraries have a URL now. Another session published
the 21 pinned files as the pre-release `per-family-v1.1.0-dev.20261005` on
`hugocornellier/mediapipe_flutter_native` and pointed `familyRuntimeBaseUrl`
at it on `feat/per-family-hosting` (`a8212da`, on `02b80a3`), then ran CI and
Test Lab there (see [Verification](#verification)). That branch now also
carries its fixes for what CI found, plus copies of `47229d9`, `475534f` and
`a7eed82`. Rebased onto this branch at `a7eed82`, it applies cleanly: the
copies drop out as already here, and its five own commits follow. It was
rebased here, and both landed in one PR, #77.

1. **Repo-only cleanup:** items 5, 7, 12 and 16, plus the source-build half of
   item 9. Remove the CI jobs that call deleted scripts in the same step, and
   note that main's ruleset must drop or rename `official-runtime-pin` when this
   reaches main.
2. **Shipped code and packaging:** items 1, 2, 4, 10, 11, 13, 14 and 19.
3. **Examples:** item 3, after porting the tests it names.
4. **When Google's libraries have a URL:** item 8 and the consumer half of
   item 9, as `PER_FAMILY_RUNTIMES.md` ("Before merging") already plans.
5. **Replaced by [Open before publishing](#open-before-publishing).**
   Re-run the dry-runs and compare with the table in the overview; publish
   `mediapipe_core`, switch the families from `path:` to
   `mediapipe_core: ^0.1.0`, publish the families.
   **Dry-runs re-run after step 4** (clean export of `f90dd15`): core 43 KB,
   audio 31 KB, text 32 KB, vision 305 KB (from 62, 33, 203 and 509 KB at
   `6c940cf`). The only error is the expected one, the families' `path:`
   dependency on core. Repository: 864 tracked files and 290,304 lines (from
   1,002 and 302,376 at `6c940cf`, 1,634 and 415,007 at `4b37b72`; lines
   counted with `git grep -c ''` on text files at each commit).
6. **After launch:** items 6, 15, 17 and 18. **All done before launch, in step 6.**

## Re-measuring

```sh
# Repository totals at a commit (-I skips binary files)
git ls-tree -r --name-only <commit> | wc -l
git grep -I -c '' <commit> -- . | awk -F: '{s+=$NF} END {print s}'

# Dart in the packages' lib/
git grep -I -c '' <commit> -- 'packages/*/lib/*.dart' | awk -F: '{s+=$NF} END {print s}'

# What pub.dev would receive: dry runs on clean copies, never --force.
# Add mediapipe-task-decision and mediapipe-task-retrieval to FAMILY first (item 21).
python3 -B packages/mediapipe-core/tool/publish_check.py
```

`publish_check.py` replaces the loop this section used to show. That loop ran
inside the repository, where pub applies the repository's `.gitignore` and
the packages' `publish_to: none`.
