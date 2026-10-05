# Audio stream mode

**Status:** Shipped (2026-10-04, written against main `3e217ac`): "What
shipped" records the code and where the evidence departed from the plan.

`AudioRunningMode.audioStream` is the third streaming piece, after vision's
live stream mode (`ec77d66`, #68) and the gallery's video file mode
(`3e217ac`, #69). A caller feeds blocks of any length with `classifyAsync`
and listens to `results`, which delivers one result per model window; nothing
is dropped, and `dispose()` flushes the tail. Google's own stream runs it on
Android, iOS, macOS, Linux and Windows, and a Dart emulation on Google's clips
mode runs it in browsers, where Google has no stream. This plan supersedes the
"Audio stream mode" section of
`packages/mediapipe-task-vision/tool/LIVE_STREAM.md` (lines 413 to 521), which
becomes a pointer to this file when the code lands. It corrects that section
in eight places, of which three change the design: Google stamps the flushed
tail with a sentinel instead of a time, Google's C callback carries no user
data and no error message, and the checks and the emulation need the model's
window, rate and channels, which only the model's metadata holds.

Paths are relative to the repository root, except under "File by file" and
"Tests", where a path that starts with `lib/`, `test/`, `native/`, `hook/`,
`android/` or `assets/` belongs to the package its heading names, the audio
package unless the heading says otherwise. Paths that start with `mediapipe/`
are Google's source at tag `v1.0.0` (commit `6d31f1e`,
https://github.com/google-ai-edge/mediapipe/blob/v1.0.0/), read from the local
checkout `build/codex-tmp/mediapipe-native`.

## What shipped

- **API.** `AudioClassifier.classifyAsync(block, timestampMilliseconds:)` and
  `results`, as "The contract" says, with its messages to the letter; the
  parity snapshot gained exactly these two members, identical on native and
  web. `classify` on a stream task, and `classifyAsync` or `results` on a
  clips task, throw `StateError` in vision's wording.
- **Shared Dart** (`lib/src/stream/`). `model_specs.dart` reads the window,
  rate and channels at the field offsets of Google's own generated readers in
  the 1.0.0 wheel (`schema_py_generated.py`, `metadata_schema_py_generated.py`),
  which give YAMNet's `[15600]` input, 16 kHz and one channel, inline or by
  offset. `checks.dart` is the contract's table, in its order. `results.dart`
  holds the stream, the clock, the tail's restamping and the one place a
  failure ends the stream. `emulation.dart` frames as decision 3 says. Core's
  `checkStreamTimestamp` and `maxStreamTimestampMilliseconds`
  (`packages/mediapipe-core/lib/src/stream_timestamps.dart`) are vision's
  rule, which vision now calls. Google's sentinel lives in `google_tail_io.dart`,
  picked by a conditional import, since dart2js refuses an integer literal
  above 2^53; browsers never receive it. Runners: `AudioStreamRunner` beside
  the clips runner, with `EmulatedStreamRunner` for browsers and
  `BackendStreamRunner` for Android in `lib/src/runner.dart`, and the worker
  in `lib/src/io/native_audio_stream.dart` for the desktops and iOS.
- **The bridge** (`native/audio_stream_bridge.c`): Google's structs as C
  views, the deep copy and 64 slots, each callback posting its copy's address
  to the stream's worker with `Dart_PostCObject` (`NativeApi.postCObject`) and
  the end as a null message. The hook compiles it with the text hook's flags
  wherever core has a runtime.
- **iOS** (`packages/mediapipe-core/native/ios/audio_sdk_bridge.mm`): stream
  mode with a delegate the handle keeps, the private queue read at creation,
  `MpAudioClassifierClassifyAsync`, and a close that waits on the queue. An SDK
  that hid the queue would make creation fail with `kMpUnimplemented`. The
  close releases the handle even when the SDK's close fails, where Google's C
  API keeps it (upstream-issues.md UP-041).
- **Android.** The plugin creates `AUDIO_STREAM` tasks with a result listener
  and an error listener that emit `update`s under the request the Dart side
  chose at `create`; `send` loads the interleaved samples with their channel
  count and calls `classifyAsync` with the timestamp read by core's new
  `TaskHost.wholeNumber`. The adapter installs `audioStreamBackendFactory`,
  routes updates by request and ends the stream with the reply to `close`.
- **Gallery.** The microphone mode runs its own stream task:
  `lib/audio/microphone.dart` has `PcmBlocks` (an odd byte carried, a chunk
  too short to advance the millisecond held back) and two
  `MicrophoneSource`s, the recorder and the speech sample played in 100 ms
  chunks of an odd number of bytes. Window times show three decimals, so the
  975 ms steps are visible, and a settings change replaces the stream task
  without losing audio. Opening the stream takes its turn with the settings'
  rebuilds, so the two never open two tasks; leaving the mode while the
  stream or the recorder is still starting closes what started, and a
  rebuild that fails stops the microphone, as a failed stream does, rather
  than keep its audio waiting. Device tests pass the sample as
  `GalleryApp(microphone:)`; browsers take it with `?microphone=sample`.
- **CI.** `make test_audio` runs the bridge's AddressSanitizer test
  (`make test_audio_stream_bridge`), as macOS CI's `make test_only` does, and
  `tool/test_text_audio.py` runs it on Linux. No workflow ran the audio
  package's browser tests before; `web.yaml` now runs `test/web` as
  JavaScript and as WebAssembly (`make test_audio_web` locally).

### Where the evidence departed from the plan

1. **The callback's threads.** On core's macOS library the callbacks of one
   stream ran on MediaPipe's pool threads, three changes in five calls, never
   the caller's thread; each call finished before the next began (with every
   call made to take 300 ms, all of them waited), and none came after
   `MpAudioClassifierClose` returned, which waited for the running one. The
   table above said "one MediaPipe thread"; it is corrected. The design did
   not depend on it.
2. **A desktop graph failure never reaches the callback.** Google's task
   runner hands the callback only successful packets
   (`mediapipe/tasks/cc/core/task_runner.cc`), so the C callback's status path
   is unreachable from Google's runtime; a graph failure surfaces as "Graph
   has errors: ..." from the next `MpAudioClassifierClassifyAsync`
   (`calculator_graph.cc`) and from the close, both with Google's message, and
   reaches `results` as a `TaskException` with that message. The worker still
   decodes a failed callback as decision 10 says, and the fakes test it.
3. **A hot restart could crash the app: the bridge posts to a port.** With
   the planned `NativeCallable.listener`, a debug hot restart while Google's
   graph worked through half an hour of queued audio aborted the macOS app:
   "runtime_entry.cc: 5380: error: Callback invoked after it has been
   deleted." The restart kills the worker isolate, the VM deletes its
   listener, and Google's graph, never closed, calls on. A `NativeFinalizer`
   could not close that gap: it runs some time after the isolate is gone,
   while the listener is deleted at once. So each slot keeps the worker's port
   instead, and the bridge posts each copy's address with `Dart_PostCObject`,
   which a gone isolate's port refuses; the bridge then frees the copy. With
   that, the same restart went through: the first run heard 27 windows and
   ended with "Audio stream worker exited", and the second heard exactly its
   own 1,846 windows while the first run's graph worked through some 1,800
   more. A slot and Google's graph left open by a hot restart stay taken until
   the app restarts, which the 65th stream's message says. The lock replaces
   the planned compare-and-swap because freeing a slot must also wait out a
   callback that is posting to it. The text package's streams still use a
   `NativeCallable.listener` and keep the exposure; this change does not touch
   them.
4. **The iOS probe passed.** On the simulator (iOS 26.4, SDK 1.0.1) the
   private queue exists (`_callbackQueue`, an `OS_dispatch_queue_serial`
   labelled `com.mediapipe.tasks.audio.audioClassifier_<UUID>`). Over 200 runs
   of the lone half second, an empty block run on it after `closeWithError:`
   found exactly one result every time, stamped 9223372036854775 by both the
   delegate and the result; the result had already arrived before that block
   in only 144 of the 200, so the wait is needed.
5. **The Android probe.** On the API 31 arm64 emulator, through the plugin's
   channel before the Dart adapter existed: the listener ran on MediaPipe's
   `Thread-N` threads, a different one from call to call, never the platform
   thread; the tail's `update` reached Dart before the reply to `close` in 50
   of 50 runs; its raw timestamp was the sentinel; a first timestamp of
   3,000,000,000 ms went through `wholeNumber` whole; stereo blocks matched
   mono. Google refused at the call an older or equal timestamp ("The
   received packets having a smaller timestamp than the processed timestamp.")
   and a changed rate, and the stream went on. No graph failure could be
   forced with the valid model, so the late report of correction 6 stays
   documented (UP-039) and tested on fakes.
6. **The reference.** The stream reference from the 1.0.0 macOS wheel matches
   the table above case by case, and a second run reproduced it byte for byte;
   `speech-odd` logged Google's timestamp warning seven times and passed (risk
   4). The checked-in clips reference names `mediapipe==1.0.1`, which wrote it
   before macOS moved to 1.0.0; the 1.0.0 wheel reproduces every value, so it
   was left as it is. The generator stamps each block with
   `first_timestamp_ms + frames_sent * 1000 // rate`; the runtime suite's
   one-sample case, where that would repeat a millisecond, is not in the
   reference but in the oracle test, which bumps the stamp.
7. **The browser seam is `?microphone=sample`, not `?test-hooks`**, which
   also turns on per-frame writes on every live camera page the browser
   journey opens.
8. **The approximation, measured again.** With Google's 1.0.0 wheel, the
   emulation against Google's stream over every score of every window (a
   throwaway script, as the plan's probes were): at 16 kHz 0 on speech and on
   a 13 s mix of speech, reversed speech, noise and a chirp; speech 0 at 48
   and 32 kHz and one step of 1/256 at 44.1, 22.05 and 8 kHz, the plan's
   figures; the mix 13 to 22 steps in 4 to 9 of 14 windows, where Google's
   whole-clip clips mode is 10 to 22 steps from its stream on the same audio.
   The README states these.
9. **No multi-channel model exists** (risk 9), so the channel mismatch is
   tested on fake models in the VM and browser suites; the browser probe
   checks the rate and timestamp messages and that the mono YAMNet accepts a
   stereo block.
10. **The delay readout** is measured when the next window arrives, since one
    window's audio ends where the next one starts; the gallery cannot know an
    uploaded model's window without reading the model, so it shows from the
    second window on.
11. **Unchanged:** `android/proguard-rules.pro` (a minimal release app built
    with R8 streamed on the emulator: 3000000000 to 3000003900 ms, Speech four
    times and the Tick tail, no error), the web worker and the browser plugin,
    and `tool/coverage/matrix.json`, which has no mode axis; #68 added none for
    live stream mode either. `LIVE_STREAM.md`'s audio section is now a pointer
    here; the citations of it above are to `3e217ac`.

### Verified

- **macOS:** the audio package's 47 VM tests (the 22 of the fake-backend
  suite, the 15 of the runtime suite against Google's stream, the 10 of clips
  mode), its 4 Flutter-tagged adapter tests, and the browser suite's 24 in
  Chrome as JavaScript and as WebAssembly; the bridge's AddressSanitizer test;
  the oracle at 0.0 over 12,504 scores; core's 110 tests; vision's 253 (and
  107 that skip on macOS by design, and 12 Flutter-tagged), which run core's
  timestamp rule now; text's 67 and 8; the gallery's suites on macOS, run
  again after the bridge moved to ports: `audio_task_test.dart` (2), the
  journey (2, the microphone mode's stream included), `runtime_test.dart`
  (3), both still image suites, `assets_test.dart` and `text_tasks_test.dart`;
  the gallery's 88 widget tests, of which the three where leaving the mode or
  a settings change overtakes the stream's start fail on the page before
  that handling (the journey and `audio_task_test.dart` ran again after it);
  the API parity check; `tool/check_docs.py`; `make analyze` and
  `make check_format`.
- **iOS simulator** (iOS 26.4): `sdk_text_audio_test.dart` 3 of 3, after the
  move to ports too: the stream equals the same device's clips results with a
  difference of 0.0, Google's raw sentinel arrives at the adapter, and
  `dispose()` takes 12 ms; the gallery journey 2 of 2, the microphone mode's
  stream included.
- **Android emulator** (`mp_hand_api31`, API 31 arm64): the CPU reference
  suites, `sdk_text_audio_test.dart` (3 of 3: 0.0 against the same device's
  clips results, Google's sentinel at the adapter, `dispose()` in 7 ms), the
  detection (6), embedder (2), landmark (6), segmenter (2) and Interactive
  Segmenter (1, its GPU case skipped) suites, one launch each.
  `sdk_all_test.dart` in one launch stops at its first GPU step, the face
  camera's switch to the GPU, which this arm64 emulator offers and its
  emulated GL cannot run; CI's x86_64 emulator, which never offers the GPU,
  runs it whole, the gallery journey included.
- **Chromium**, on a release web build of every task CI bundles:
  `test_browser.mjs --suite=text-audio` (the emulated stream equal to
  Google's JavaScript, error 0, and to Google's whole 48 kHz clip, error 0;
  the fake microphone's windows at 0, 975 and 1950 ms), the default
  `test_browser.mjs` suite (runtime, API and webcam), and the gallery journey,
  16 tasks and 56 checks, the microphone mode's stream included.
- **CI**, the branch's first run, every workflow green with no rerun: on
  Linux x64 (Google's 1.0.1 wheel) and Windows x64 (1.0.0) the host's wheel
  wrote the stream reference again and every case equals the checked-in one,
  difference 0.0; the audio package's 47 tests pass against it, with the
  bridge built by the hook's flags (MSVC's `/W4 /WX` on Windows); and the
  oracle prints 0.0 over 12,504 scores on both, which settles risk 6. CI's
  x64 Android emulator and arm64 iOS simulator: the stream test (0.0, five
  results, `dispose()` in 10 and 18 ms) and the journey's
  `audio_classifier:cpu:stream`. Browsers: the audio package's browser tests
  as JavaScript and as WebAssembly; the text-audio suite, error 0 against
  Google's JavaScript and 0 against Google's whole 48 kHz clip, in Chromium
  (both runtimes), Firefox and WebKit; the journey's microphone mode in
  Chromium, Firefox and WebKit. The second run, on `ed3f467` with the page's
  turn-taking, gave the same differences, all 0.0, and was green after one
  rerun: its WebKit journey stalled in Pose Landmarker's video file mode at
  54 of 90 frames, with no crash, as main's `3e217ac` did at the same step
  on its first attempt, and the rerun passed. The third run, on `46706cd`,
  which changed only this file, failed the Chromium hand webcam check twice
  (median 0.0206 and 0.0195 against a tolerance of 0.015): both captures
  meant to show the preview without its overlay still showed the overlay, so
  Google's IMAGE task read drawn-on pixels. The same code had passed with
  clean captures (median 0.0041); the owner chose a third attempt, which
  passed with a clean capture (median 0.0044). The race is in the camera
  suite's wait for a frame drawn without the overlay, not in this change.
- **Firebase Test Lab**, one run on `ed3f467`: on every phone the suite's
  runner logged all 39 tests passed, on the Pixel 8a (API 35) in 8:21, the
  Galaxy S24 (API 34) in 5:36 and the Galaxy A12 (API 31) in 30:18. The
  stream test logged a difference of 0.0 against each phone's own clips
  results, five results, and `dispose()` in 32, 39 and 72 ms, and no phone
  logged a `Mediapipe error`. The A12's 30:18 passed Test Lab's 30-minute
  limit, which cut its instrumentation and records the execution as timed
  out. Against the last A12 pass (#68, 17:48 in all), the gallery journey's
  nine vision pages with a video file step, which #69 added and which had
  never run on the A12 (its run hit the quota), took 589 s more; this change
  added the stream test's 5.2 s and 5.3 s on the journey's audio page, its
  microphone mode; the rest is variation between runs (modern text,
  unchanged, took 85 s more). The owner accepted the A12's result without a
  second run. Since `ed3f467` this commit removed vision's
  `VisionTaskChecks.maxTimestampMilliseconds`, which the timestamp rule's
  move to core had left to one test, and corrected the stream limit's
  wording (iOS and the desktops only, a limit of this package's bridge
  rather than of Google's runtime); nothing the phones ran behaves
  differently.

## How this was checked

- **Source.** Every claim of the old section was read against the code at
  `3e217ac` and Google's `v1.0.0` source. Google has published no `v1.0.1`
  source tag (its newest tag is `v1.0.0`), while this repository runs 1.0.1 on
  iOS, on Linux and in browsers and 1.0.0 on Android, macOS and Windows
  (`packages/mediapipe-task-audio/README.md:16-20`). So the 1.0.1 runtimes
  can be checked by behaviour only.
- **Behaviour.** Throwaway Python probes drove Google's wheels in
  `AUDIO_STREAM` mode on macOS arm64 with the pinned YAMNet model and the
  repository's fixtures: `mediapipe==1.0.0` (the wheel pinned in
  `packages/mediapipe-core/tool/official_wheels.py:12-21`) and
  `mediapipe==1.0.1` (`build/codex-tmp/official-python-1.0.1`). Both printed
  the same results, character for character, in every probe. The rates other
  than 16 and 48 kHz were made from the 48 kHz fixture by linear
  interpolation, so they exercise the resampler and are not recordings. The
  probes are not kept; the reference generator in "Tests" reproduces every
  number that matters.
- **Not verified when the plan was written.** Nothing had run on Android,
  iOS, Linux, Windows or in a browser. Each such point is marked "Not
  verified" where it appears and has a probe in "Risks and unknowns"; "What
  shipped" records what the probes and the tests found since.

What the probes showed. The rows about rates compare all 521 scores of
every window; the rows about block shapes compare the top three scores to six
places:

| Case | Result |
| --- | --- |
| Speech fixture at 16 kHz, 100 ms blocks | Results at 0, 975, 1950 and 2925 ms while streaming, equal to clips mode; the close delivers one more, equal to the clip's last chunk, stamped 9223372036854775 ms |
| Blocks of 777 samples, first timestamp 5000 ms | Same scores; results at 5000, 5975, 6950 and 7925 ms: the first block's timestamp plus 975 ms per window, whatever the later blocks say |
| The first second as 16,000 blocks of one sample | The first window's result unchanged, then a tail on the close; 1.8 s in total |
| A lone 500 ms block | Nothing while streaming; exactly one result during the close |
| Exactly two windows (31,200 samples) | Two results; nothing during the close |
| No blocks | No result |
| Stereo with both channels equal, mono model | Equal to the mono stream |
| Speech fixture at 48 kHz | Stream equal to clips mode on the whole clip, tail included |
| Stream fed in blocks of 1000, 4096 or one block | Identical: the result does not depend on the block size |
| A 13 s synthetic mix (speech, reversed speech, noise, a chirp) at 48, 44.1, 32, 22.05 and 8 kHz | Stream and whole-clip clips mode differ in a few windows, by 1 to 22 steps of 1/256; per-window clips mode differs from the stream by 1 to 22 steps too, in the same range |
| The same mix at 16 kHz | Stream, whole clip and per-window all equal, difference 0.0 |
| The callback | On MediaPipe's own threads, never the caller's (corrected by the C probe: not always the same thread, one call at a time) |
| Same or older timestamp | Refused at the call: "Input timestamp must be monotonically increasing." |
| Changed sample rate | Refused at the call: "The input audio sample rate: 48000 is inconsistent with the previously provided: 16000" |
| A block stamped 5 s late | Accepted |
| Stream mode without a callback | Creation refused |

## Corrections to the current section

Each item quotes or paraphrases `LIVE_STREAM.md` and states what the code
says.

1. **"The only graph difference is `AudioToTensorCalculator`'s `stream_mode`
   ... with the model's window and overlap from its metadata"
   (`LIVE_STREAM.md:425-429`).** Two things are wrong.
   - There is a second difference. In stream mode the graph does not connect
     the calculator's `TIMESTAMPS` output to the postprocessing
     (`mediapipe/tasks/cc/audio/audio_classifier/audio_classifier_graph.cc:248-253`),
     so there is no aggregation by time: each window leaves on the
     `CLASSIFICATIONS` stream as its own result, stamped with its packet's
     time
     (`mediapipe/tasks/cc/components/calculators/classification_aggregation_calculator.cc:191`),
     where clips mode returns a list stamped relative to the clip's start
     (the same file, line 204).
   - There is no overlap, ever. The graph sets only the channels, the window,
     the rate and the mode (`audio_classifier_graph.cc:101-108`), and the
     specification it reads hard-codes `num_overlapping_samples = 0`
     (`mediapipe/tasks/cc/audio/utils/audio_tensor_specs.cc:159`). The window
     is the input tensor's last dimension divided by the channels, and the
     rate and channels come from the model's metadata
     (`audio_tensor_specs.cc:154-157`). So "when the model's windows do not
     overlap" (`LIVE_STREAM.md:484-485`) is always true.
2. **"A final short block yields one more result during the close"
   (`LIVE_STREAM.md:439-442`).** True, and the probes confirm it, but three
   facts are missing.
   - The tail carries no time. The calculator's flush mode defaults to
     `ENTIRE_TAIL_AT_TIMESTAMP_MAX`
     (`mediapipe/calculators/tensor/audio_to_tensor_calculator.proto:70`),
     which the graph never changes, so the tail is one tensor sent at
     `Timestamp::Max()` (`audio_to_tensor_calculator.cc:570-599`), and its
     result reports that sentinel divided by 1000: 9223372036854775 ms, on
     both wheels. Android divides the same packet time by 1000
     (`mediapipe/tasks/java/com/google/mediapipe/tasks/audio/audioclassifier/AudioClassifier.java:162-169`)
     and so does iOS
     (`mediapipe/tasks/ios/audio/audio_classifier/sources/MPPAudioClassifier.mm:192-194`).
     A browser cannot hold that number: it is above 2^53.
   - `padding_samples_after` is 0 for this task, since the graph never sets
     it, so only the resampler's remainder is appended
     (`audio_to_tensor_calculator.cc:373-383`).
   - The tail is at most one window: a remainder that the resampler's flush
     pushes past one window is cut to it
     (`audio_to_tensor_calculator.cc:593-597`), and an empty remainder gives
     no result at all.
3. **"With the same rule as vision's: the callback runs on a MediaPipe thread
   and its arguments are valid only during the call"
   (`LIVE_STREAM.md:443-447`).** True, and two differences from the text
   package's callbacks are missing.
   - The callback has no user data:
     `void (*)(MpStatus status, MpAudioClassifierResult* result)`
     (`mediapipe/tasks/c/audio/audio_classifier/audio_classifier.h:68-70`).
     `text_stream_bridge.c` finds its Dart receiver through the `userdata`
     pointer Google passes back
     (`packages/mediapipe-task-text/native/text_stream_bridge.c:43-48`). The
     audio shim cannot, so it needs one C function per open stream.
   - A failure arrives as a status code with a null result and no message
     (`mediapipe/tasks/c/audio/audio_classifier/audio_classifier.cc:72-75`).
     A success carries exactly one result, freed when the callback returns
     (the same file, lines 77-85).
   - Google's header is C++, not C: it includes `<cstddef>`
     (`mediapipe/tasks/c/audio/core/common.h:19`) and gives a struct member a
     default value and a nested typedef (`audio_classifier.h:63-70`). A C
     shim must declare its own views of the structs, as the text bridge does.
4. **"`ClassifyAsync(block, sampleRate, timestampMs)` returns at once"
   (`LIVE_STREAM.md:420`).** Usually. `TaskRunner::Send` adds the packet to
   the graph's input stream (`mediapipe/tasks/cc/core/task_runner.cc:337-345`),
   which waits while the stream holds its limit of 100 packets
   (`mediapipe/framework/calculator_graph.cc:291-292`, mode
   `WAIT_TILL_NOT_FULL`, `mediapipe/framework/calculator_graph.h:112-125`). A
   caller that feeds faster than inference runs is held there, so the native
   call must not run on the UI isolate.
5. **The jitter check "only logs a warning" (`LIVE_STREAM.md:435-438`).**
   True, with a detail the documentation needs: the warning fires when a
   block's timestamp is more than half a sample period (31 microseconds at
   16 kHz) from the first timestamp plus the samples received, and is written
   every twentieth time (`mediapipe/util/time_series_util.cc:48-59`). With
   timestamps in whole milliseconds almost every microphone block qualifies,
   so Google's log repeats the warning; it is harmless.
6. **"The Android SDK has `classifyAsync(AudioData, timestampMs)` ... with a
   result listener; the iOS SDK has ... a stream delegate"
   (`LIVE_STREAM.md:447-451`).** True, and each hides a trap.
   - Android reports a graph failure late. The task wires the error listener
     to the output handler only (`AudioClassifier.java:199`), which hears
     result conversion errors
     (`mediapipe/tasks/java/com/google/mediapipe/tasks/core/OutputHandler.java:147-166`).
     The runner has no error listener, so `send` logs and swallows a graph
     error (`.../core/TaskRunner.java:276-282`) and `close` throws it
     (`TaskRunner.java:222-239`, `334-340`). A refused timestamp throws from
     `classifyAsync` itself (`TaskRunner.java:300-308`).
   - iOS holds its delegate weakly
     (`mediapipe/tasks/ios/audio/audio_classifier/sources/MPPAudioClassifierOptions.h:80-81`,
     the same in the pinned 1.0.1 SDK's header) and hands every result to a
     private serial queue with `dispatch_async` (`MPPAudioClassifier.mm:96-97`,
     `177-200`). `closeWithError:` only closes the C++ runner
     (`mediapipe/tasks/ios/core/sources/MPPTaskRunner.mm:112-114`), so it
     returns before the delegate has received the last results, and the
     public API offers no way to wait for them.
   - Android and iOS take interleaved channels as they are
     (`.../audio/core/BaseAudioTaskApi.java:144-153`,
     `mediapipe/tasks/ios/audio/core/sources/MPPAudioPacketCreator.mm:66-71`).
     The comment "Google's browser and mobile tasks read one channel"
     (`packages/mediapipe-task-audio/lib/src/runner.dart:63-64`) is right for
     browsers only (`mediapipe/tasks/web/audio/audio_classifier/audio_classifier.ts:180-186`).
7. **"It keeps the last 15,600 samples and classifies that window again as
   audio arrives, so windows are re-run per update"
   (`LIVE_STREAM.md:459-462`).** The page does not slide or re-run. It
   collects samples until it has 15,600, classifies the newest 15,600, clears
   its buffer, and drops the window altogether while the previous one is still
   being classified (`gallery/lib/audio_page.dart:182-212`). Every result is a
   one-window clip, so every entry in the list is stamped 0 ms. It also drops
   a trailing odd byte of a recorder chunk, which shifts every later sample by
   one byte (`audio_page.dart:183-186`).
8. **"Checked in Dart before the runtime ... a channel count other than the
   model's is refused unless the model is mono" (`LIVE_STREAM.md:475-478`)
   and "a reference clip fed as 100 ms blocks gives the clip's results,
   timestamps included" (`LIVE_STREAM.md:508-510`).**
   - Dart does not know the model's channels today, nor its window or rate.
     The check, the emulation's framing and the tail's timestamp all need
     them, so Dart must read them from the model file ("Decisions", 5).
   - The equality with clips mode holds at the model's rate, tail included
     once the tail's sentinel is replaced by its start time. With resampling
     it holds for the speech fixture and is not a general property: Google's
     stream and its clips mode use two entry points of the same resampler and
     their results part by up to 22/256 in single windows of a noisy signal.
     The reference for the native stream must therefore be Google's stream,
     not Google's clips.

The rest of the section stands: sample rate fixed by the first block and a
change refused
(`mediapipe/tasks/cc/audio/core/base_audio_task_api.h:87-101`), timestamps
strictly increasing (`task_runner.cc:330-335`), the mixdown of any input to a
mono model and the refusal of a mismatch otherwise
(`audio_to_tensor_calculator.cc:349-364`), no flow limiter
(`AudioClassifier.java:200-212`), the web's lone `classify` and its TODO
(`audio_classifier.ts:147`), the native classifier's `Isolate.run` per clip
(`packages/mediapipe-task-audio/lib/src/io/native_audio_classifier.dart:95-97`),
the iOS bridge's refusal of stream mode
(`packages/mediapipe-core/native/ios/audio_sdk_bridge.mm:63-65`), the Android
plugin's clips mode
(`packages/mediapipe-task-audio/android/src/main/java/dev/mediapipe/flutter/audio/MediaPipeAudioPlugin.java:49`)
and the web worker's `classify`
(`packages/mediapipe-task-audio/assets/worker.js:36`).

## The contract

The owner's contract, unchanged, with the points this plan had to settle
marked "(settled here)".

- `AudioClassifier.create` with `runningMode: AudioRunningMode.audioStream`.
- `void classifyAsync(AudioData block, {required int timestampMilliseconds})`
  returns at once: the checks throw synchronously, the block then belongs to
  the task.
- `Stream<AudioClassifierResult> get results`: one result per model window
  with its timestamp; one subscription, made before the first block
  (`StateError` otherwise); pausing buffers; cancelling discards; a failure
  arrives as a `TaskException`, closes the stream and poisons the task.
- Nothing is dropped. Blocks may be any length; each yields zero or more
  results. An empty block passes the checks, reserves its timestamp and never
  reaches the runtime (settled here: Google's handling of a zero-length
  matrix is not verified, and a recorder may deliver one).
- The first block fixes the sample rate. A mono model mixes any input down;
  otherwise the block's channels must equal the model's. Timestamps strictly
  increase. All checked in Dart, with one message on every platform.
- `dispose()` flushes the tail as Google does, delivers what that yields,
  then closes `results`. Disposing twice is one disposal.
- `classify` on a stream task and `classifyAsync` or `results` on a clips
  task throw `StateError` (settled here, as vision's `results` does in the
  other modes).
- Native on Android, iOS, macOS, Linux and Windows; emulated on the web.
- One identical API on all six platforms; `tool/api_parity` shows no native
  or web difference.

The messages, the same everywhere:

| Check | Throws |
| --- | --- |
| Disposed | `StateError('AudioClassifier has been disposed.')`, as today (`packages/mediapipe-task-audio/lib/src/audio_classifier.dart:60`) |
| A failure ended the task | The same `TaskException` again |
| Wrong mode | `StateError('AudioClassifier was created in audioClips mode; this method requires audioStream mode.')`, vision's wording (`packages/mediapipe-task-vision/lib/src/runner/checks.dart:83-89`) |
| No listener | `StateError('Listen to AudioClassifier.results before submitting the first block.')`, vision's wording (`checks.dart:64-68`) |
| Sample rate changed | `ArgumentError.value(block.sampleRate, 'sampleRate', 'The stream runs at 16000.0 Hz, fixed by its first block')` |
| Channel mismatch | `ArgumentError.value(block.channels, 'channels', 'The model requires 2 channel(s)')` |
| Timestamp | `ArgumentError.value(timestampMilliseconds, 'timestampMilliseconds', 'Must be nonnegative, strictly increasing and at most 9007199254740')`, vision's rule and limit (`checks.dart:17`, `92-104`) |

The checks run in that order, so a block refused for its rate or channels
does not reserve its timestamp.

## Decisions

### 1. Native on the five native platforms, emulated on the web: confirmed

The recommendation stands, for one reason the probes make precise: only
Google's stream reproduces Google's stream when the input is resampled.

- At the model's rate the emulation is exact. With no resampler, the window
  tensors of the stream and of clips mode are the same floats, and both pad
  the tail with zeros (`audio_to_tensor_calculator.cc:494-498`). Measured
  difference: 0.0 over all 521 scores of every window, tail included, on the
  speech fixture and on a 14-window synthetic mix, on both wheels.
- With resampling, nothing but the streaming resampler gives the stream's
  floats. Stream mode keeps one `QResampler` across blocks
  (`audio_to_tensor_calculator.cc:412-415`, `453-467`); clips mode calls the
  one-shot `QResampleSignal` (the same file, lines 442-448). Both are
  time-aligned, yet their results differ in a few windows of a noisy signal
  by up to 22/256, because YAMNet is quantized and amplifies a difference in
  the last bits. An emulation, which can only call clips mode, inherits that
  difference.
- The cost of native is real and listed under "Risks": a C shim with a fixed
  number of slots, a wait for a private queue on iOS, and failures that
  Android reports only at the close.

The emulation is written against any clips classifier, not against the web
(decision 6), so it is also the oracle of the native path at the model's
rate, and a platform whose native path cannot be proven can ship emulated
without any change to the API. That is the fallback for iOS if its probe
fails ("Risks", 2).

### 2. A result's timestamp

Google's rule, the same on every native platform: the first block's timestamp
becomes the first window's (`audio_to_tensor_calculator.cc:393-396`), each
window adds `round(windowSamples / modelRate * 1e6)` microseconds (lines
576-584), and the result reports microseconds divided by 1000
(`classification_aggregation_calculator.cc:191`). Later blocks' timestamps
never enter it; they only have to increase. For YAMNet the step is exactly
975,000 microseconds, so window `k` is at `t0 + 975 k` ms, which the probe
shows for `t0 = 0` and `t0 = 5000`.

In Dart, one function serves every platform:
`t0 + (k * stepMicroseconds) ~/ 1000`, with `t0` the timestamp of the first
block that holds samples. Adding the whole milliseconds outside the division
gives the same number as Google's division of the sum, and keeps the
arithmetic below 2^53 in browsers.

- **Full windows.** The native paths deliver Google's own value. The
  emulation computes it. The tests assert the two are equal on every native
  platform, so the function is proven against Google rather than assumed.
- **The tail.** Google reports the sentinel 9223372036854775. Dart replaces
  it with the function's value for the tail's index, which is where the
  tail's audio starts and what clips mode reports for the same padded chunk
  (3900 ms on the speech fixture). The reason is the contract itself: a
  browser cannot represent the sentinel, so the API could not be identical on
  six platforms, and a sentinel is useless to a caller that draws a
  timeline. The adapters' tests still assert that the raw value from Google
  is the sentinel, which is the proof that the result came from Google's
  flush. This is question 1 for the owner.

### 3. Resampling

- **Native.** Google's streaming resampler, untouched. The stream's results
  do not depend on how the audio is cut into blocks (measured with blocks of
  1000, 4096 and the whole signal).
- **Web.** Per-window resampling by Google's own clips mode is an acceptable
  approximation, and a resampler that keeps state across windows is not worth
  building. The emulation cuts the input, at the input's rate, into the
  spans that make one model window each, classifies each span as a clip and
  keeps the first chunk. Measured against Google's stream on the wheel:

  | Input rate | Speech fixture | Synthetic mix, worst window |
  | --- | --- | --- |
  | 16 kHz | 0 | 0 |
  | 48 kHz | 0 | 3/256 (whole clip in clips mode: 3/256) |
  | 44.1 kHz | 1/256 | 6/256 (whole clip: 3/256) |
  | 32 kHz | 0 | 22/256 (whole clip: 22/256) |
  | 22.05 kHz | 1/256 | 22/256 (whole clip: 6/256) |
  | 8 kHz | 1/256 | 7/256 (whole clip: 13/256) |

  The emulation is as far from Google's stream as Google's clips mode is: in
  most windows not at all, in a few by some steps of 1/256. A Dart port of
  `QResampler` (a Kaiser-windowed polyphase filter, about 300 lines, with its
  own oracle to maintain) would not close the gap, since Dart cannot
  reproduce the C++ filter's float arithmetic bit for bit, and the last bits
  are what the quantized model amplifies. The README states the
  approximation.
- **Framing at another rate.** One window is `P = windowSamples * rate /
  modelRate` input frames, which need not be whole (42,997.5 at 44.1 kHz).
  Window `k` is the frames from `floor(k * P)` to `ceil((k + 1) * P)`, and is
  complete once the stream holds that many. Clips mode returns two chunks for
  such a span at any rate but the model's, because the one-shot resampler's
  flush runs past the window (probe: 46,800 frames at 48 kHz give a second,
  all-padding chunk heard as "Silence"), so only the first chunk is kept. At
  the model's rate the span is exactly the window and clips mode returns one
  chunk.
- **The tail.** Whatever remains short of a window is classified as a clip
  on `dispose()`, first chunk kept; nothing remains, no result.

### 4. Channels

Google's rule, checked in Dart at each block with the model's channel count
from decision 5: a model with one channel accepts any count and Google mixes
it down (`audio_to_tensor_calculator.cc:349-364`); any other model requires
its own count. Google mixes each block on its own, so a stream to a mono model
may change its channel count between blocks, and Dart allows what Google
allows.

- **Android, iOS, desktop.** The block's interleaved samples and channel
  count go to Google as they are, so Google's own mixdown runs.
- **Web.** Google's browser task takes one channel
  (`audio_classifier.ts:180-186`), so the emulation averages the channels in
  Dart, as clips mode does today
  (`packages/mediapipe-task-audio/lib/src/runner.dart:94-106`). A model with
  more than one channel cannot run in a browser in either mode; Google's
  runtime says so.
- Clips mode keeps its behaviour. Its comment about mobile tasks is corrected
  and nothing else.

### 5. Dart reads the model's audio input

The channel check, the emulation's framing and every computed timestamp need
three numbers Google reads from the model: the window in samples, the rate
and the channels (`audio_tensor_specs.cc:154-157`). No Google API returns
them, so a small reader in Dart takes them from the model's bytes: the first
subgraph's first input tensor's shape in the TFLite flatbuffer, and the
`AudioProperties` of that tensor in the `TFLITE_METADATA` buffer
(`mediapipe/tasks/metadata/metadata_schema.fbs:262-268`, union member 4 of
`ContentProperties`, lines 301-307). A 40-line Python reader of exactly those
fields returned 15,600 samples, 16,000 Hz and 1 channel for the pinned YAMNet,
so the reader is about 100 lines of Dart with no dependency.

- A stream task is created by Google first, so an invalid model fails with
  Google's message as it does today. The reader runs next; a model Google
  accepted but the reader cannot read fails creation with a `TaskException`
  that says which field is missing, and the task is closed.
- The bytes come from `options.modelBytes`, or from `options.modelPath`: a
  file read on native platforms, a fetch in browsers, where the bytes then go
  to the worker in place of the URL so the model is downloaded once.

### 6. One emulation, used twice

`EmulatedAudioStream` takes a clips classifier as a function (samples, rate,
channels to results), accumulates frames, frames them as decision 3 says and
stamps them as decision 2 says. The web runner gives it the browser backend.
The oracle test gives it the native clips task. It processes one window at a
time, in order.

### 7. A paused or slow listener, and a slow runtime

Nothing is dropped anywhere, so three queues can grow, and the README names
them.

- **Results.** A paused or slow listener's results wait in the Dart stream.
  With the default `maxResults: -1` a YAMNet result holds 521 categories,
  roughly 50 KB, about 3 MB per minute of audio; with `maxResults: 3` it is
  negligible. Cancelling discards results from then on.
- **Audio, when blocks arrive faster than inference.** On desktop and iOS,
  Google's graph holds up to 100 blocks and then holds the worker isolate in
  the call (correction 4), so further blocks wait in the worker's port. On
  Android they wait in the plugin's executor. In browsers they wait as
  samples in the emulation's buffer. A second of backlog is 64 KB at 16 kHz
  mono and 384 KB at 48 kHz stereo. A microphone cannot outrun YAMNet; a file
  fed at once can, and its whole audio is then in memory until it is
  classified.
- **Google's buffer** holds less than one window.

No counter of pending blocks is added: the contract has none, and a caller
that needs back-pressure can pace by the results it receives.

### 8. Where the stream state lives

| Platform | Checks, clock, results stream | Blocks travel | Google's state | Results return |
| --- | --- | --- | --- | --- |
| macOS, Linux, Windows | The caller's isolate | `SendPort` to one worker isolate per task, which calls `MpAudioClassifierClassifyAsync` | Google's graph: resampler, sample buffer, input queue | Google's callback on a MediaPipe thread calls the shim, which copies the result and posts the copy's address to a `ReceivePort` in the worker with `Dart_PostCObject`; the worker decodes it and sends it to the caller's isolate |
| iOS | The same | The same worker and the same bindings | The SDK's graph, behind core's bridge | The SDK's delegate, on the SDK's private serial queue, calls the same shim through the bridge |
| Android | The caller's isolate | The method channel to `TaskHost`'s worker thread, which calls `classifyAsync` | The SDK's graph | The SDK's result listener, on a MediaPipe thread, calls `TaskHost.emit`, which posts an `update` to the main thread and so to Dart |
| Web | The caller's isolate, the emulation's sample buffer included | One `classify` message to the web worker per window | None between calls: clips mode | The worker's reply |

The worker isolate owns the native task from creation to close, as the text
worker does (`packages/mediapipe-task-text/lib/src/io/text_task_worker.dart`),
because `MpAudioClassifierClassifyAsync` can wait (correction 4) and
`MpAudioClassifierClose` runs the tail's inference. The worker's port
receives the copies, so the callback thread only copies and posts and never
waits for Dart. (Planned as a `NativeCallable.listener`, as in
`native_text_stream.dart`; the hot restart probe changed it, "What shipped".)

### 9. The flush on dispose

| Platform | What `dispose()` does | Why every result arrives before the stream closes |
| --- | --- | --- |
| macOS, Linux, Windows | The worker drains its port, calls `MpAudioClassifierClose`, then asks the shim to post an end to the same port as the results | `TaskRunner::Close` closes the inputs and waits for the graph (`task_runner.cc:350-366`), so the tail's callback has run when it returns; the end reaches the same port, after it |
| iOS | The same Dart code; the bridge's `MpAudioClassifierClose` calls `closeWithError:` and then runs an empty block synchronously on the SDK's callback queue | The results were queued on that serial queue before `closeWithError:` returned (correction 6), so the empty block runs after the last of them |
| Android | The channel's `close` runs `classifier.close()` on the worker thread | `TaskRunner.close` waits for the graph (`TaskRunner.java:226-229`), the listener's `emit` posts each `update` to the main thread before that returns, and the reply to `close` is posted after them (`TaskHost.java:153`, `181-187`) |
| Web | The emulation waits for the windows in flight, classifies the remainder as a clip, then closes the worker | It is all one Dart queue |

How to prove Google flushes, per platform:

1. A lone 500 ms block yields no result while streaming and exactly one
   during `dispose()`, equal to Google's Python wheel for the same block.
2. At the adapter (the worker's decoder, the plugin's update, the bridge's
   callback), that result's raw timestamp is Google's sentinel
   9223372036854775, which no code of ours produces.
3. Exactly two windows yield two results and nothing during `dispose()`; no
   blocks yield nothing.

A paused listener receives the tail and the end once it resumes; `dispose()`
does not wait for it, as vision's does not
(`packages/mediapipe-task-vision/lib/src/runner/live_stream.dart:105-110`).

### 10. Errors

- **Dart's checks** throw from `classifyAsync` with the messages above.
- **Creation** fails as today: `RuntimeUnavailableException` for a missing
  runtime or the GPU delegate, `TaskException` with Google's message for a
  bad model. New: a `TaskException` when no stream slot is free (decision
  11) and when the model's audio input cannot be read (decision 5).
- **A block Google refuses at the call** (its message is available: the C
  API's `error_msg`, the SDK's `NSError`, Java's exception) becomes a
  `TaskException` on `results`, since `classifyAsync` has already returned.
  Dart's checks make these unreachable in normal use.
- **A graph failure.** Desktop: the callback's status, as
  `TaskException('Google\'s audio stream failed: INVALID_ARGUMENT (status
  3).', statusCode: 3)`, because the C API passes no message (correction 3).
  iOS: the same, through the bridge, which logs the `NSError`'s description
  since the C callback cannot carry it. Android: the exception `close` throws,
  with Google's message, so it reaches `results` during `dispose()` and not
  before (correction 6).
- **Every failure** is delivered once on `results`, closes the stream, and
  poisons the task: later calls throw the same exception. `dispose()` still
  closes Google's task and frees the slot.
- "One message on every platform" therefore holds for the checks, which is
  what the contract asks; a graph failure's text is Google's and differs by
  platform.

### 11. The C shim's slots

Because Google's callback has no user data, the shim holds a fixed table of
64 callback functions, generated by a macro, each bound to one slot. Creating
a stream takes a free slot and stores in it the worker's port and
`Dart_PostCObject` to post to it; the close frees it. Creating a 65th
concurrent stream throws a `TaskException` that says so. 64 is far above any
app's need and costs 64 small functions. One lock guards the table, since
tasks on different worker isolates take and free slots at once, and a
callback holds it while it posts, so that once a slot is freed nothing posts
for its old stream. (Planned as a compare-and-swap over a listener's function
pointer; "What shipped" says why it changed.) This is question 3 for the
owner.

### 12. The timestamp rule moves to core

`VisionTaskChecks._timestamp` and its limit are the rule the audio stream
needs, and the audio package cannot import vision. The rule moves to core's
platform interface, beside `checkClassifierSettings`, and vision calls it
(`tool/SHARED_CODE.md`, item 1, is the precedent), so the two packages cannot
drift apart. Vision's message and tests stay as they are.

## File by file

### `packages/mediapipe-core`

- `lib/platform_interface.dart` and a new `lib/src/stream_timestamps.dart`:
  the timestamp rule and `maxStreamTimestampMilliseconds` (decision 12).
- `native/ios/audio_sdk_bridge.mm`:
  - `MpAudioClassifierInternal` gains the stream delegate (held strongly,
    since the SDK holds it weakly) and the C callback.
  - `MpAudioClassifierCreate` accepts `kMpAudioRunningModeAudioStream`, which
    requires `result_callback`, and sets
    `sdk.audioClassifierStreamDelegate` and `MPPAudioRunningModeAudioStream`;
    the refusal at lines 63-65 goes.
  - A private delegate class implements
    `audioClassifier:didFinishClassificationWithResult:timestampInMilliseconds:error:`:
    an error calls the callback with its status and a null result; a result
    is copied with the existing `CopyClassifications` into a one-result
    `MpAudioClassifierResult` stamped with the delegate's timestamp, passed
    to the callback and freed.
  - `MpAudioClassifierClassifyAsync`, already declared in the vendored header
    (`native/ios/include/mediapipe/tasks/c/audio/audio_classifier/audio_classifier.h:120-122`),
    builds the `MPPAudioData` as `MpAudioClassifierClassify` does and calls
    `classifyAsyncAudioBlock:timestampInMilliseconds:error:`.
  - `MpAudioClassifierClose`, for a stream, calls `closeWithError:`, waits
    for the SDK's callback queue (decision 9), then releases. Today's
    `CloseHandle` only drops the reference
    (`native/ios/sdk_bridge_support.h:131-139`), which is enough for clips.
  - The header comment and `native/ios/README.md` say the bridge serves both
    modes.
- `android/src/main/java/dev/mediapipe/flutter/core/TaskHost.java`: one new
  helper for a whole-number argument as a `long`. `number()` returns an `int`
  (lines 190-194), and a timestamp in milliseconds passes 2^31 after 25 days,
  which a wall-clock stamp does at once. Nothing else changes: `emit` (lines
  181-187) already sends updates from any thread.
- `upstream-issues.md` (repository root): entries after UP-036 for the tail's
  sentinel timestamp, the C callback without user data or message, the Java
  runner's swallowed graph errors, and the iOS close that returns before its
  delegate calls. Also two defects seen while reading: the C callback frees
  with `delete[]` what it allocated with `new`
  (`mediapipe/tasks/c/audio/audio_classifier/audio_classifier.cc:77-85`,
  `159-168`), and `MpAudioClassifierClose` keeps the task when the close
  fails (lines 180-188).

### `packages/mediapipe-task-audio`, shared Dart

- `lib/src/types.dart`: the TODO at lines 45-47 goes; `audioStream`'s comment
  describes the mode; `AudioClassifierResult.timestampMilliseconds` says what
  it is in each mode.
- `lib/src/audio_classifier.dart`: the rejection and its TODO at lines 39-45
  go. `classifyAsync` and `results` are added and `classify` checks the
  mode. `create` opens, by mode and platform, the clips runner or one of the
  three stream runners, and reads the model's audio input for a stream
  (decision 5). The class comment shows both modes.
- New `lib/src/stream/model_specs.dart`: `AudioModelSpecs` (window samples,
  sample rate, channels, and the step in microseconds) and the flatbuffer
  reader. It handles a missing table or field by naming it, and a buffer
  stored by offset and size as well as inline.
- New `lib/src/stream/checks.dart`: `AudioStreamChecks`, the table in "The
  contract": mode, listener, disposal, failure, the rate fixed by the first
  block, the channel rule, and core's timestamp rule.
- New `lib/src/stream/results.dart`: the single-subscription controller, the
  clock of decision 2 (the first timestamp, the window count, the tail's
  timestamp, the sentinel's replacement), and the one place a failure is
  delivered, the stream closed and the task poisoned.
- New `lib/src/stream/emulation.dart`: `EmulatedAudioStream` (decisions 3
  and 6).
- `lib/src/runner.dart`: `AudioClassifierRunner` gains the stream's two
  operations. New runners: one over `EmulatedAudioStream` for a clips
  backend (the web), one over a stream backend (Android). The comment at
  lines 63-64 is corrected.
- `lib/src/audio_task_backend.dart`: a second, optional factory,
  `audioStreamBackendFactory`, with its interface (send a block with its
  rate, channels and timestamp; a stream of result maps; dispose). Android
  installs it; the web does not, which is how the runner knows to emulate.
- A pair of small files for the model's bytes from a path: `dart:io` on
  native platforms, a fetch in browsers.

### `packages/mediapipe-task-audio`, desktop and iOS

- New `native/audio_stream_bridge.h` and `.c`, modelled on
  `packages/mediapipe-task-text/native/text_stream_bridge.c`:
  - C views of Google's `MpCategory`, `MpClassifications`,
    `MpClassificationResult` and `MpAudioClassifierResult`, since Google's
    header is C++ (correction 3), with the export macro of
    `text_stream_bridge.h:9-13`, which Windows needs.
  - `MpFlutterAudioEvent`: an owned deep copy of one result (status,
    timestamp, heads, categories, strings) and a copy-error code, freed with
    `MpFlutterAudioEventFree`.
  - `MpFlutterAudioStreamAcquire(post, port, &callback)` returns a slot and
    the slot's callback for `MpAudioClassifierOptions.result_callback`;
    `MpFlutterAudioStreamEnd(slot)` posts null, the end, to the slot's port;
    `MpFlutterAudioStreamRelease(slot)` frees the slot.
  - Each slot's callback copies inside Google's call and posts the copy's
    address; after that it touches nothing of Google's, and a refused post
    leaves the copy to the bridge to free.
- New `native/audio_stream_bridge_test.c`, run under AddressSanitizer as the
  text one is (`Makefile:214-215`, `tool/test_modern_text.py:69-71`): the deep
  copy, a null result with a status, slots taken and freed from several
  threads, the 65th refused, a callback on a freed slot ignored.
- `hook/build.dart`: `CBuilder.library` for the shim, for every target core
  has a runtime for, with the text hook's flags
  (`packages/mediapipe-task-text/hook/build.dart:27-35`).
- `pubspec.yaml`: `native_toolchain_c: ^0.19.3`, the version the text
  package uses (`packages/mediapipe-task-text/pubspec.yaml:38`). It is new to
  this package and not to the repository; it is what compiling the shim
  takes. This is question 4 for the owner.
- `lib/src/third_party/mediapipe/audio_classifier_bindings.dart`: the missing
  binding for `MpAudioClassifierClassifyAsync`. The options struct already
  has `runningMode` and `resultCallback` (lines 45-55).
- New `lib/src/third_party/mediapipe/audio_stream_bindings.dart`: the shim's
  bindings, as `text_stream_bindings.dart` binds the text bridge.
- New `lib/src/io/native_audio_stream.dart`: the worker isolate. It copies
  the model bytes, opens the port for the copies, takes a slot, creates Google's task
  with running mode 2 and the slot's callback, and reports ready or the
  error. Then it serves its port: a block calls
  `MpAudioClassifierClassifyAsync` (Google copies the samples,
  `audio_classifier.cc:88-99`, so the buffer is freed after the call); the
  close request calls `MpAudioClassifierClose`, asks the shim to post the
  end, waits for it, frees the slot, closes the port, frees the model, and
  exits. A worker that dies fails the task, as the text worker does.
- `lib/src/io/native_audio_classifier.dart`: `openNativeAudioClassifier`
  opens the stream worker for stream mode; the clips path is unchanged.

### `packages/mediapipe-task-audio`, Android

- `android/src/main/java/dev/mediapipe/flutter/audio/MediaPipeAudioPlugin.java`:
  - `create` reads `runningMode`. For `AUDIO_STREAM` it sets
    `RunningMode.AUDIO_STREAM`, a result listener that emits each result as
    the clips JSON plus `timestampMs` (the result's own, which for the tail
    is the sentinel) under the request id from the call, and an error
    listener that emits the message. Google requires the listener
    (`AudioClassifier.java:381-386`).
  - A new method `send`, added to the host's set at line 33: an `AudioData`
    with the block's channels and rate, loaded with the interleaved samples,
    then `classifyAsync` with the timestamp read as a `long`.
  - `close` is unchanged: `classifier.close()` flushes.
- `lib/mediapipe_audio_android.dart`: installs `audioStreamBackendFactory`.
  The stream backend sets the channel's method call handler when the first
  task is created, not at registration, for the reason the text adapter
  records (`packages/mediapipe-task-text/lib/mediapipe_text_android.dart:44-52`),
  routes each `update` by request id, turns a failed `send` or `close` into
  the stream's error, and closes its stream when the reply to `close`
  arrives.
- `android/proguard-rules.pro`: no change expected. The listeners are this
  plugin's lambdas and Google's classes are already kept. Not verified under
  R8; see "Risks", 8.

### `packages/mediapipe-task-audio`, web

- `lib/mediapipe_audio_web.dart` and `assets/worker.js`: no change. The
  emulation calls the existing `classify` once per window.

### The gallery

- `gallery/lib/audio_page.dart`:
  - The microphone mode opens its own task in `audioStream` mode, listens to
    `results` and prepends each result to the list (newest first, eight
    kept). The clips task stays for the clips mode; each is created when its
    mode opens and both are disposed with the page and on a settings change.
  - Recorder chunks become blocks: 16-bit samples to floats, an odd byte
    carried to the next chunk, and `classifyAsync` with the timestamp of the
    block's first sample, counted from the samples sent
    (`sent * 1000 ~/ 16000`). A chunk too short to advance the millisecond
    waits for the next.
  - `_pending`, `_classifying`, `_window`, the window cutting and the
    dropping at lines 182-212 go. The entries now show each window's start
    time in the stream instead of 0.00 s.
  - Leaving the mode stops the recorder and disposes the stream task, which
    flushes the tail.
  - The status line shows the delay from the end of a window's audio to its
    result in place of "Done in", which one clip call measured. The card's
    text says that Google frames the stream.
  - A source seam: the page reads blocks from a function that returns the
    recorder's stream by default. Integration tests replace it, and a
    browser page opened with `?test-hooks`
    (`gallery/lib/web/test_hooks.dart:9`) uses the speech sample cut into
    100 ms blocks, since CI has no microphone outside Chromium.
- No change to the preparer: `record` is already a gallery dependency
  (`gallery/tool/prepare.py:327`).

### Removal of the reservations

`git grep -n "TODO.*audio stream"` must print nothing but this file's and
`LIVE_STREAM.md`'s own mentions of the command, and the
`throwsUnsupportedError` expectation in
`packages/mediapipe-task-audio/test/audio_classifier_test.dart:186-194`
becomes a stream test.

## Tests

### The reference from Google's wheel

`packages/mediapipe-task-audio/tool/generate_audio_reference.py` gains a
second output, `test/fixtures/official_stream_reference.json`, written by the
same run that writes the clips reference, with `mediapipe==1.0.0`:

```sh
/opt/homebrew/bin/python3.10 -B \
  packages/mediapipe-task-audio/tool/prepare_audio_reference.py
```

`prepare_audio_reference.py` installs the wheel pinned for the host
(`official_wheels.py`, 1.0.0 on macOS arm64) into
`build/codex-tmp/official-python-1.0.0`, runs the generator and writes the
provenance receipt. The checked-in file is the macOS output; on Linux and
Windows CI the same script regenerates it with the host's pinned wheel
(Linux 1.0.1, Windows 1.0.0) and the suite reads it through
`MEDIAPIPE_AUDIO_REFERENCE_DIR`, exactly as for clips
(`tool/test_text_audio.py:64-70`).

The generator creates the classifier in `AUDIO_STREAM` mode with
`max_results=3`, feeds each case's blocks with `classify_async`, waits for
the full windows it expects, notes how many results arrived, then closes,
which joins Google's dispatcher, and records what arrived during the close.
For each case it stores the clip, the block length, the first timestamp, and
per result the raw timestamp, the top three names and scores, and whether it
arrived during the close. Cases:

| Case | Clip | Blocks | Proves |
| --- | --- | --- | --- |
| `speech-100ms` | speech, 16 kHz | 1600 samples | Windows that straddle blocks; four results and a tail |
| `speech-odd` | speech, 16 kHz | 777 samples, first timestamp 5000 ms | Odd block lengths; timestamps from the first block |
| `speech-one-block` | speech, 16 kHz | the whole clip | Several results from one block |
| `speech-48k` | speech, 48 kHz | 4801 samples | Google's streaming resampler with odd blocks |
| `speech-stereo` | speech, 16 kHz, duplicated to two channels | 1600 frames | The mixdown |
| `two-heads` | the 15,600-sample clip | 1600 samples | A stream that ends on a window: one result, no tail |
| `lone-half-second` | first 8000 samples of speech | one block | The flushed tail alone |

### Fake-backend unit suite, `test/audio_stream_test.dart`

Through the public class, with a fake clips backend and a fake stream
backend installed through the platform interface, and a model built by the
test with chosen specs:

- A block before a listener throws; a second listener throws; pausing
  buffers and resuming delivers in order; cancelling discards and blocks keep
  being processed.
- The rate is fixed by the first block and a change throws without reserving
  the timestamp; a stereo block to a mono model is accepted and to a
  three-channel model refused; a mono model accepts a change of channel
  count; timestamps negative, equal, older and above the limit throw, with
  the exact messages.
- `classify` on a stream task and `classifyAsync` or `results` on a clips
  task throw `StateError`; every call after `dispose()` throws.
- The emulation's framing: windows that straddle blocks, blocks of one
  sample and of three windows, an empty block, the spans at 44.1 kHz
  (0 to 42,998, 42,997 to 85,995, ...), only the first chunk kept when the
  backend returns two, timestamps from a first timestamp of 0 and of 5000,
  and the tail's timestamp.
- The stream backend's path: results in order, the sentinel replaced by the
  tail's start, a result during the close delivered before the stream ends.
- A backend failure reaches the listener once, closes the stream and poisons
  `classifyAsync`; `dispose()` then still closes the backend; `dispose()`
  twice returns one future; `dispose()` with a paused listener completes.
- The specs reader: YAMNet's numbers; a truncated file, a model without
  metadata and one with image metadata each name what is missing.

`test/android_adapter_test.dart` gains the stream: the `create` arguments,
one `send` per block with channels and a 64-bit timestamp, `update` routed by
request, an `update` with `error`, and the stream closed by the reply to
`close`.

### Runtime suite on the desktops, `test/audio_stream_runtime_test.dart`

Run by `make test_audio` on macOS and by `tool/test_text_audio.py` on Linux
and Windows.

- **Against Google's wheel.** Every case of the reference: the same number
  of results, the same timestamps (the tail's compared after the documented
  replacement), the same names, scores within 0.00001. The tolerance is the
  clips suite's (`test/audio_classifier_test.dart:18-20`): the same library
  on the same host, with the reference rounded to six places.
- **The oracle.** For the 16 kHz cases, `EmulatedAudioStream` over the
  native clips task and the native stream give the same timestamps,
  categories and scores, with a tolerance of zero. The reason: at the
  model's rate no resampler runs, so both feed the model the same floats and
  the same zero padding, in the same library. The wheel shows 0.0 over 521
  scores in every window. The test prints the largest difference, as
  `live_stream_runtime_test.dart` does; a nonzero value on Linux or Windows
  is a finding to explain, not a tolerance to raise ("Risks", 6).
- **Timestamps.** The native results' own timestamps equal the Dart clock's
  for every full window.
- **The flush.** The lone half second: nothing before `dispose()`, one
  result during it, and through a test hook in the worker's decoder its raw
  timestamp is 9223372036854775.
- **Refusals reach Google never.** A rate change and a channel mismatch throw
  in Dart, and the stream goes on to give the reference's results afterwards.
- **Lifetime.** Two streams at once keep their results apart; 64 streams
  open and the 65th fails with the slot message; a stream disposed with
  blocks still queued delivers all its results first.
- **Struct layouts.** The existing size test covers the options struct; the
  shim's event struct gets its own.

### Browsers

- `test/web/audio_stream_web_test.dart` (the emulation and the checks on a
  fake backend, compiled to JavaScript and to WebAssembly, since the
  timestamp arithmetic must hold with JavaScript numbers), run in Chromium
  like `test/web/decoders_test.dart`.
- `gallery/tool/web_text_audio_probe.dart` gains a stream section, and
  `gallery/tool/browser/test_browser.mjs --suite=text-audio` checks it in
  Chromium, Firefox and WebKit, which CI runs (`.github/workflows/web.yaml`).
  The script computes Google's answers on the same page with Google's
  JavaScript, as it does for clips:
  - 16 kHz speech in 100 ms blocks through the Dart stream equals Google's
    `classify` of the whole clip, every number, tail included: at the model's
    rate the emulation is exact.
  - 48 kHz speech through the Dart stream equals Google's `classify` of each
    46,800-sample span, first chunk, every number: that proves the Dart
    framing. Against Google's `classify` of the whole 48 kHz clip, the same
    top categories with scores within 2/256: that documents the
    approximation, with the gallery's existing bound for another runtime
    (`gallery/integration_test/sdk_text_audio_test.dart:22-23`).
  - The lone half second, a rate change, a channel mismatch and the timestamp
    rule, with the same messages as native.
  - With `?mic=1` in Chromium, whose fake microphone plays the speech sample
    (`test_browser.mjs:845-856`), the probe's microphone section feeds the
    recorder's chunks to a stream task and hears speech in results whose
    timestamps increase.

### Mobile, `gallery/integration_test/sdk_text_audio_test.dart`

A third test, run on the iOS simulator and the Android emulator in CI and on
the Test Lab phones through `sdk_all_test.dart`:

- 16 kHz speech in 100 ms blocks: five results at 0, 975, 1950, 2925 and
  3900 ms; equal to the same device's clips results with a tolerance of
  zero, for the oracle's reason; within 2/256 of the checked-in reference.
- 48 kHz speech in blocks of 4801: five results, within 2/256 of the stream
  reference's `speech-48k` case.
- The stereo case equals the mono one. As far as the suites show, this is
  the first stereo audio through either SDK in this repository.
- The lone half second: one result, during `dispose()` only.
- A refused rate change, after which the stream still works.
- A log line `SDK_TEXT_AUDIO {"event":"audio_stream", ...}` with the largest
  score difference, the result count and the milliseconds `dispose()` took.

### The gallery's microphone mode

- `gallery/integration_test/audio_task_test.dart` (macOS, Linux, Windows):
  the speech sample as a stream gives the clip's five results.
- `gallery/integration_test/gallery_journey_test.dart`, in its audio case
  (line 349), on every platform that runs the journey: with the source seam
  feeding the speech sample, tap `audio-source-microphone`, wait for four
  windows, check that their start times increase by 975 ms and that the
  first hears "Speech", then switch back to clips and see the clip's
  results. The flush is proven by the suites above, not by the page.
- `gallery/tool/browser/test_gallery_journey.mjs`, in its audio branch (line
  217), in Chromium, Firefox and WebKit: the same steps on the page opened
  with `?test-hooks`.
- A widget test of the page with a fake task: an odd byte carried between
  chunks, a chunk too short to advance the timestamp, the list capped at
  eight, a failure shown, the task disposed when the mode closes.

### Firebase Test Lab

One run of `android-face-testlab.yml` on the branch after CI is green. The
stream test rides in the one `sdk_all_test.dart` execution per phone, so it
costs no extra execution, and it feeds the fixtures as fast as they are
accepted: about twenty YAMNet inferences, which matters on the Galaxy A12,
close to the 30 minute limit. Check, per phone (Galaxy S24, Pixel 8a, Galaxy
A12):

- the stream test passed, and its log line in logcat: a score difference of
  zero against the phone's own clips results, five results, and the time the
  flush took;
- no `Mediapipe error` line from Google's runner during the stream, which is
  where a swallowed graph failure would show (correction 6);
- the run's total time against the last run's, for the A12's margin.

The phones' microphones are not exercised: the test runs under the
integration test driver, which cannot grant the recording permission the way
a user does. Not verified; this is question 5 for the owner.

## Docs that ship with the code

- `packages/mediapipe-task-audio/README.md`: `runningMode` in the options
  paragraph (lines 66-71) loses "reserved and refused". The "Keep one
  classifier for a live stream" paragraph (lines 100-101) becomes a section
  "Live audio" with a sample that listens to `results` and feeds blocks, and
  that states: one result per window with its start time; the first block
  fixes the rate; timestamps from the sample count keep Google's log quiet;
  `dispose()` flushes; nothing is dropped and what that means for memory;
  native on five platforms and emulated in browsers, with the measured
  approximation at rates other than the model's; the limit of 64 concurrent
  native streams. "Validation" gains the stream reference and the oracle.
  `tool/check_docs.py` must still pass.
- `packages/mediapipe-task-audio/CHANGELOG.md`, under 0.2.0: audio stream
  mode on every platform; `classifyAsync` and `results`; the line that calls
  `audioStream` reserved (lines 11-12) is edited.
- `packages/mediapipe-task-audio/MIGRATION.md`, 0.1.0 to 0.2.0: the sentence
  at lines 19-20 changes, and a note says that `create` no longer throws
  `UnsupportedError` for `audioStream`, so code that caught it to fall back
  to clips now gets a stream task.
- `tool/api_parity/snapshots/audio.txt`: `dart run bin/api_parity.dart
  --update` adds exactly `void classifyAsync(AudioData block, {required int
  timestampMilliseconds})` and `Stream<AudioClassifierResult> get results`;
  no `audio.web.txt` appears and `baseline.txt` does not grow.
- This file: the status line becomes "Shipped" with the commit, and a "What
  shipped" section records where the code differs from the plan, as
  `LIVE_STREAM.md` does.
- `packages/mediapipe-task-vision/tool/LIVE_STREAM.md`: the status paragraph
  and "Order of work" say the audio stream shipped; the "Audio stream mode"
  section shrinks to a pointer to this file.
- `tool/API_UNIFICATION.md`: the status (lines 3-4), the note that
  `audioStream` is reserved (lines 227-228) and phase 7 (line 396).
- `upstream-issues.md`: the new entries.
- `tool/coverage/matrix.json`: Not verified whether a mode needs a row; the
  implementer checks how live stream mode was recorded in #68 and follows it.

## Risks and unknowns

Each has a probe that settles it before the code that depends on it.

1. **The C callback's thread and lifetime.** Read from source and seen on
   the macOS wheels: MediaPipe's own threads, arguments freed after the call,
   every callback done when the close returns. Probe: a C harness of about
   60 lines against core's macOS library that creates a stream, feeds the
   fixture, prints the thread of each callback and whether any arrives after
   `MpAudioClassifierClose` returns. Not verified: that the Linux 1.0.1 and
   Windows 1.0.0 libraries export `MpAudioClassifierClassifyAsync`. Google's
   Python binds it on every desktop, which makes it very likely. Probe: list
   the exports of the two pinned wheels' libraries on the Mac before writing
   the worker.
2. **The iOS flush.** The bridge must wait for the SDK's private callback
   queue. The plan reads it with key-value coding
   (`[classifier valueForKey:@"_callbackQueue"]`), which the v1.0.0 source
   supports (`MPPAudioClassifier.mm:50-54`); the 1.0.1 SDK is closed and its
   binary shows no symbol to confirm it. Not verified. Probe, first thing on
   iOS: on the simulator, create a stream classifier and read the queue; then
   run the lone half second 200 times and require one result every time. If
   the queue cannot be read, the bridge refuses stream mode and the options
   are a wait on the classifier's deallocation (the queued blocks hold it,
   `MPPAudioClassifier.mm:177-200`, an inference from the same closed
   source) or the emulation on iOS, which changes decision 1 for one
   platform and goes back to the owner.
3. **Android's listener.** Read from source only. Probe on the API 31 arm64
   emulator, before the Dart adapter: a stream created from the plugin with
   a log in the listener, the fixture, and the lone half second; confirm the
   listener's thread, that the tail's `update` reaches Dart before the reply
   to `close`, and the tail's raw timestamp. Then force a graph failure, if
   one can be forced with a valid model, and confirm it surfaces at `close`.
   If none can be forced, the late report stays documented and untested.
4. **The jitter warning.** Google logs it every twentieth late block and
   never fails the stream. Probe: the reference generator's
   `speech-odd` case stamps whole milliseconds on 777-sample blocks, which
   triggers it; the case passing is the proof. The README says how to avoid
   the noise.
5. **A timestamp bound without a result.** Google's runner observes bound
   changes (`task_runner.cc:163-173`) and its audio converter reads the
   packet without checking that one is there
   (`mediapipe/tasks/cc/audio/audio_classifier/audio_classifier.cc:116-124`).
   No empty callback appeared in any probe, 16,000 one-sample blocks
   included. If one appears on another platform it would crash inside
   Google's library; the one-sample case in the runtime suite is the watch
   for it.
6. **Scores on x86_64.** The zero tolerance of the oracle is measured on
   arm64 only. Google's x86_64 wheels have shown run-to-run differences in
   generated text before. Probe: the oracle test's printed largest difference
   on the first Linux and Windows CI run. If it is not zero, compare two
   native stream runs with each other first, to tell nondeterminism from a
   real difference.
7. **A stream alive at a hot restart.** The worker isolate dies without
   closing Google's task, so the graph lives on, its slot stays taken and its
   callback points at a listener whose isolate is gone. Not verified what
   `NativeCallable.listener` does then; the text streams have the same
   exposure. Probe: on macOS in debug, hot restart during a microphone
   stream and feed nothing more; then a second probe where the old graph
   still holds a tail. If a late callback can crash, the shim clears a
   slot's sink on a new acquisition with the same owner, or the worker
   registers the task for core's cleanup, whichever the probe supports.
8. **R8.** The release build shrinks the plugin; the stream adds listeners.
   CI's release consumer check covers creation only. Probe: one local
   `flutter build apk --release` of the gallery and the stream test's log on
   the emulator.
9. **A model with several channels.** The repository has none, so the
   mismatch check and a native multi-channel stream are tested with a fake
   and by reading. Not verified against Google's runtime.
10. **The recorder.** Not verified: the chunk sizes `record` delivers per
    platform, and that every platform honours 16 kHz. The page's block code
    does not assume a chunk size: it carries odd bytes. It passes the rate it
    asked the recorder for, as the page did before, since `record` reports
    none (corrected: this said "the rate the recorder reports").
11. **Firefox and WebKit.** The emulation was measured with the wheel, not in
    a browser. The probe page in CI is the check; Firefox cannot be run on
    this Mac.

## Order of work

Work in a worktree, `.claude/worktrees/audio-stream`, on a branch from main;
never switch branches in the main checkout. Resolve packages before
formatting, and prepare the gallery per target before its `pub get`.

1. **Probes** (risks 1, 2, 3 and the reference generator). Checkpoint: the
   stream reference exists and matches this plan's table; the exports, the
   iOS queue and the Android ordering are known. A failed probe changes the
   plan before any code depends on it.
2. **Shared Dart**: core's timestamp rule, the specs reader, the checks, the
   results clock, the emulation, the fake-backend suite. Checkpoint: `dart
   test` in the audio package and the vision package's tests, on macOS.
3. **Desktop**: the shim with its C test, the hook, the bindings, the worker,
   the runtime suite. Checkpoint: `make test_audio` and
   `python3 -B tool/test_text_audio.py` on macOS, the oracle at 0.0.
4. **iOS**: the bridge. Checkpoint: `sdk_text_audio_test.dart` on the
   simulator.
5. **Android**: the plugin and the adapter. Checkpoint: the adapter test,
   and the CPU suites on the API 31 arm64 emulator `mp_hand_api31` (the API
   35 emulator crashes inside Google's library, and GPU failures on arm64
   emulators are expected and not this change's).
6. **Web**: the emulation runner, the browser unit test, the probe page.
   Checkpoint: the web build and `test_browser.mjs --suite=text-audio` in
   Chromium, with the fake microphone.
7. **Gallery**: the microphone mode, its widget test, the journeys.
   Checkpoint: the macOS gallery suites and journey, the iOS simulator's
   journey, the web journey in Chromium.
8. **Docs and cleanup**: everything under "Docs that ship with the code",
   the TODOs, `dart format` and `flutter analyze` clean, the parity tool
   with no difference. Checkpoint: the full local list below.
9. **CI**: push, open one PR whose description is the squash message (what,
   why, verified), and loop until every workflow is green with the head
   current with main. Linux, Windows and Firefox are proven here and nowhere
   else. A known flake (the jsDelivr import in Firefox, a WebKit crash on the
   hosted runner) is rerun once and named in the PR.
10. **Test Lab**: one run, after CI is green, checked as described.
11. **Land**: squash to one commit with the PR's title and number; no
    attribution lines of any kind; the owner merges.

The owner's verification list, and where each item is met:

| Required | Met by |
| --- | --- |
| All CI workflows green, head current with main | Step 9 |
| Local unit tests | Steps 2, 3, 5, 6: the audio, core and vision package suites, the C test |
| The macOS gallery suites and journey | Step 7 |
| The iOS simulator | Steps 4 and 7 |
| The web build, the gallery journey and `test_browser` in Chromium | Steps 6 and 7 |
| Firefox | CI only, step 9 |
| Android CPU suites on `mp_hand_api31` | Step 5 |
| One Test Lab run after CI is green | Step 10 |
| Python references with `/opt/homebrew/bin/python3.10` | Step 1 |

Repository rules that bind every step: one PR with one logical commit; this
plan lands in it, not in a PR of its own; no `Co-Authored-By` and no AI
attribution anywhere; no em dashes; contacts are never named; no force push
to main and no bare `git stash`; comments are full sentences that state
reasons; the gallery's generated `pubspec.yaml`, `assets/manifest.json` and
Linux and Windows plugin files are never committed.

## Questions for the owner

Answered by the owner on 2026-10-04, before the work started:

1. The tail's timestamp: the start time, computed in Dart; the tests still
   assert Google's sentinel at the adapter.
2. The web's resampling: Google's clips mode per window, with the measured
   approximation documented; no port of the resampler.
3. A fixed limit of 64 concurrent native streams, with a clear error on the
   65th.
4. `native_toolchain_c` in the audio package, at the text package's version,
   and no other dependency.
5. iOS may read the SDK's private callback queue by key-value coding,
   provided the first iOS probe passes (it did: "What shipped").
6. No permission path for real microphones on Test Lab.

The questions as they were asked:

1. **The tail's timestamp.** Google stamps the flushed tail with a sentinel,
   9223372036854775 ms, not a time. Deliver the tail's start time instead
   (3900 ms on the speech fixture), computed in Dart, or Google's sentinel?
   Recommended: the start time. A browser cannot represent the sentinel, so
   only the start time keeps the API identical on six platforms; it is what
   clips mode reports for the same chunk; and the tests still prove the
   result is Google's by asserting the sentinel at the adapter.
2. **The web's approximation.** At input rates other than the model's, the
   emulation resamples each window with Google's clips mode and differs from
   Google's stream in a few windows by some steps of 1/256 (up to 22 in one
   window of a synthetic noisy signal, at most 1 on speech), which is as far
   as Google's own clips mode is from its stream. Accept that and document
   it, or port Google's resampler to Dart? Recommended: accept. A port could
   not reproduce the C++ floats either, so it would add about 300 lines and
   an oracle to maintain without closing the gap; and at the model's rate,
   which the gallery records at, the emulation is exact.
3. **A limit of 64 concurrent native streams.** Google's C callback has no
   user data, so the shim needs one compiled callback per open stream.
   Accept a fixed 64 with a clear error on the 65th? Recommended: yes. The
   alternative is the emulation on the desktops and iOS, which gives up
   Google's streaming resampler there.
4. **`native_toolchain_c` in the audio package.** The shim needs the build
   tool the text package already uses; it is a new entry in this package's
   pubspec and no new package for the repository or an app that uses text.
   Add it? Recommended: yes. The alternative is to compile the shim in the
   text package's hook, which would make audio depend on text.
5. **iOS reads a private queue of Google's SDK.** The flush on iOS needs the
   SDK's callback queue, reached by name through key-value coding, in an SDK
   pinned by digest and proven by a test on the simulator. Accept that, or
   ship iOS emulated? Recommended: accept, provided the first probe passes;
   if it fails, emulate on iOS and say so in the README.
6. **Real microphones on Test Lab.** The one run exercises the stream with
   fixtures on three phones but not the phones' microphones, which need the
   recording permission granted under the test driver. Leave the real
   microphone to Chromium's fake device and to manual checks, or spend time
   on a permission path for Test Lab? Recommended: leave it. The stream code
   is the same for a fixture and a microphone, the recorder is a
   third-party plugin, and the quota is small.
