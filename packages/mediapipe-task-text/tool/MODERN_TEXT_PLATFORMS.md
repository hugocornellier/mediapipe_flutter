# Modern text tasks on every platform

> **Status, 2026-10-02:** implemented. EmbeddingGemma runs on Android, iOS,
> macOS, Linux, Windows and in browsers; Proofreader and Summarizer on the five
> native platforms. Each platform is compared with Google's own output for its
> runtime version, in CI, as described under "How each target is checked".
> Physical phones (Firebase Test Lab, an iPhone) have not run these tasks yet.

The rule: if the stable Google runtime a platform already uses supports a
task, the package supports it there, with the same proof as the classic text
tasks: Google's own output for the same model, runtime version and inputs,
checked in CI. `lib/src/capabilities.dart` is the source of truth for what is
claimed, and `tool/coverage/matrix.json` for what CI proves.

## Google's pinned runtimes

Checked against the exact binaries the repository pins (SHA-256 matched):
export tables, Java class files, framework headers and symbols, and npm type
declarations.

| Target | Runtime the repository pins | EmbeddingGemma | Proofreader and Summarizer |
| --- | --- | --- | --- |
| macOS arm64 | 1.0.0 wheel, `libmediapipe.dylib` | `MpTextEmbedderEmbed` with `MpTextFormatContext` | `MpTextProofreader*`, `MpTextSummarizer*` |
| Linux x64 | 1.0.1 wheel, `libmediapipe.so` | same C API | same C API |
| Windows x64 | 1.0.0 wheel, `libmediapipe.dll` | same C API | same C API |
| Android | `tasks-text` 1.0.0 | `TextEmbedder.embed(String, TextFormatContext)` | `TextProofreader`, `TextSummarizer` |
| iOS | 1.0.1 XCFrameworks | `embedText:textFormatContext:` | `MPPTextProofreader`, `MPPTextSummarizer` |
| Web | `@mediapipe/tasks-text` 1.0.1 | `TextEmbedder.embed(text, formatOptions)` | none, UP-034 |

- **Desktop:** all three libraries contain the LiteRT-LM engine the two
  generative tasks run on, and Google's Linux and Windows wheels ship the
  Python API for them, so every desktop runner produces its own reference.
- **Android:** the two tasks' JNI entry points are in
  `libmediapipe_tasks_textgenai_jni.so`, which the AAR ships for all four
  ABIs. Their options take a model path (or file descriptor) and
  `maxNumTokens`, and the Summarizer a `Mode`; they have no cache directory.
  Streaming arrives through `onNext`, `onError` and `onDone` callbacks.
- **iOS:** the headers are in MediaPipeTasksText; the classes and their
  implementations are in MediaPipeTasksCommon, which core's adapter links.
  Google publishes no C header for the two closed-source tasks, so the adapter
  declares their structs from the ABI `proofreader_bindings.dart` and
  `summarizer_bindings.dart` already use (Google's Python ctypes), and the
  example tests check those layouts against the reference's recorded ABI.
- **Web:** the 1.0.1 bundle maps all eight embedding types to EmbeddingGemma's
  prompts; `text.d.ts` declares `embed(text, formatOptions?: TextFormatOptions)`
  with `type`, `title` and `textRole`.
- **Versions:** macOS, Windows and Android run 1.0.0; Linux, iOS and web run
  1.0.1. EmbeddingGemma values move by up to 0.007 between the two on the same
  Mac (`test/fixtures/embedding_gemma/README.md`) and the generative tasks
  produce different text, so each target is compared with its own version.
- **1.1.0:** in the 1.1.0rc20260924 nightly, both options structs gained a
  trailing `min_log_severity` field. The bindings and the iOS adapter must add
  it before any pin moves to 1.1.0.

## How it is built

- **Capabilities** (`lib/src/capabilities.dart`): the generative tasks claim
  CPU on core's runtime targets (`tasksRuntimeTargets`: macOS 14+, Linux x64,
  Windows x64, iOS 15+) and on Android once the plugin registers; browsers get
  a reason citing UP-034. EmbeddingGemma claims what the classic embedder
  claims, on every platform. `test/coverage_matrix_test.dart` keeps
  `tool/coverage/matrix.json` in step with these claims.
- **Native runtime** (macOS, Linux, Windows, iOS): the FFI code is shared;
  `native_text_proofreader.dart` and `native_text_summarizer.dart` take the
  host from core's `mpHostSystem`. The text package's build hook compiles the
  callback-copy bridge (`native/text_stream_bridge.c`) for every target core
  has a runtime for. On iOS, core's `native/ios/text_sdk_bridge.mm` implements
  `MpTextProofreader*` and `MpTextSummarizer*` over Google's Objective-C
  classes, with streaming completions calling the C callback the bridge
  expects.
- **Android**: `MediaPipeTextPlugin.java` creates the two tasks from Google's
  Java options and runs `embed(text, TextFormatContext)` for the embedder. A
  `stream` method starts a request; its updates come back as `update` calls
  on the same method channel, tagged with the request, so any number of tasks
  can stream at once. Google's `onDone` ends a stream whose last update did
  not say so. `lib/src/runner/text_task_runner.dart`'s `BackendStreamTextTask`
  gives the plugin path the desktop worker's contract: requests in order, one
  subscription, pausing buffers, cancelling waits for Google's generation,
  disposal drains. A `cacheDirectory` fails on Android with a
  `RuntimeUnavailableException` naming the reason.
- **Web**: `assets/worker.js` passes the embedder's `formatContext` to
  Google's `embed(text, formatOptions)`; `mediapipe_text_web.dart` streams
  nothing, since the capability queries refuse the generative tasks first.

## How each target is checked

The standard in `CONTRIBUTING.md` applies: Google's own output for the same
model, runtime version and inputs. Generated text must match byte for byte;
embeddings keep the existing tolerance on the same host and get a bound
across builds of the same version. References replay the tests' request
order, because the Summarizer's output depends on earlier requests to the
same task.

- **macOS arm64** (`main.yaml`, "Modern text tasks / fresh macOS consumer"):
  the checked-in fixtures, from Google's 1.0.0 macOS wheel; the 32 tests in
  `example_embedding/test`.
- **Linux x64 and Windows x64** (`desktop.yaml`): `tool/test_modern_text.py`
  installs Google's wheel for the host, generates the three references with
  `tool/prepare_modern_text_reference.py`, runs the stream bridge's C test
  under AddressSanitizer (Linux; MSVC compiles the bridge on Windows inside
  the build hook), and runs the same example tests against those references
  through `MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR`. Each test first checks that
  the reference's runtime version is the one the package pins for the host.
- **iOS simulator** (`ios.yaml`): Google's 1.0.1 macOS arm64 wheel on the
  same arm64 runner is the oracle (`official_wheels.py` `ORACLES`), bundled
  into the gallery by `gallery/tool/prepare.py --modern-text-reference`;
  `gallery/integration_test/sdk_modern_text_test.dart` runs the three tasks
  through the adapter, with the lifecycle and option checks. Measured on
  2026-10-02: EmbeddingGemma and the Proofreader match the wheel byte for
  byte; the Summarizer on 8 of 10 cases, parting late in the two longest
  summaries (UP-036), so the mobile suite requires every generated text to
  follow Google's for 80 characters or in full when shorter, and logs the
  exact-match count. Google's iOS SDK also hands back non-ASCII generated
  text decoded as Mac Roman, which the adapter inverts (UP-035).
- **Android emulator** (`android.yaml`): Google's 1.0.0 Linux x86_64 wheel on
  the same runner is the oracle for the x86_64 emulator, bundled by
  `tool/gallery_builder`; the same gallery suite runs as its own launch after
  `sdk_all_test.dart` (`gallery/tool/test_android_sdk_tasks.sh`), since the
  generative models take minutes on an emulated CPU.
- **Web** (`web.yaml`): `gallery/tool/web_text_audio_probe.dart` runs
  EmbeddingGemma with Google's formatting modes, and
  `test_browser.mjs --suite=text-audio` compares every value with Google's
  JavaScript on the same page, in Chromium, Firefox and WebKit.

Every suite covers Google's reference for completed and streamed results
(streamed chunks join into the completed text), each option (`mode`,
`maxNumTokens`, `cacheDirectory` where Google accepts it), stream lifecycle
(one subscription, pausing buffers, cancelling drains and the next request
succeeds), errors (bad model path, empty input) and idempotent disposal.

## Decisions

1. **Android `cacheDirectory`:** refused with the reason, never ignored, as
   every unsupported option is in this repository.
2. **Mobile oracle:** Google's wheel of the mobile runtime's version on the
   same architecture as the simulator or emulator, generated on the CI runner.
   Where Google's builds disagree on a long generation, the disagreement is
   measured and recorded (UP-036) and the suite requires agreement from the
   start for 80 characters, rather than calling Google's SDK a second time
   on the device, which the adapter and plugin already do.
3. **Coverage matrix:** the three tasks have rows like every other task. A
   cell is `required` once its suite records rows; the capability test keeps
   the rows honest.
4. **Order:** desktop, web, iOS, then Android, since iOS reuses the desktop
   Dart path and Android needs the plugin's streaming path.

## Left to do

- Physical devices: a Firebase Test Lab phone (`android-face-testlab.yml`)
  and an iPhone, with their rows at tier `device`.
- Web Proofreader and Summarizer: when a stable `@mediapipe/tasks-text`
  declares them in `text.d.ts`, run Google's JavaScript on the fixture inputs
  and add whichever passes (UP-034).
- The gallery's text page shows the classic tasks only; the generative tasks
  have the `example_embedding` demo on desktop.
