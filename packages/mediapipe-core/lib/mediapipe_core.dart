/// What every MediaPipe task family shares, identical on Android, iOS, macOS,
/// Linux, Windows and the web: the options base, the delegate, the value
/// types results are made of, the exceptions, the model store and the
/// capability types. Each family's library exports it, so apps need not
/// import this package directly.
library;

export 'src/capabilities/task_capabilities.dart'
    show RuntimeTargets, TaskCapabilities, TaskPlatform;
export 'src/delegate.dart';
export 'src/download_asset.dart' show DownloadAsset, DownloadFailure;
export 'src/exceptions.dart';
export 'src/model_download_exception.dart';
export 'src/model_source.dart';
export 'src/model_store_io.dart'
    if (dart.library.js_interop) 'src/model_store_web.dart';
export 'src/task_options.dart' show TaskOptions;
export 'src/value_types.dart' hide cosineSimilarity;
export 'src/web_runtime.dart';

// TODO: Give apps Google's runtime logs through Dart. Nothing does today.
//
// Wanted: every line Google's runtimes log (MediaPipe's and TensorFlow
// Lite's) readable through one API exported from this library, identical on
// Android, iOS, macOS, Linux, Windows and the web. tool/api_parity checks
// that parity and snapshots the API, so its snapshots change with this. The
// API's shape is undecided.
//
// What follows was found on 2026-10-04, on main at 3e217ac, with Google's
// runtimes as pinned then: desktop 1.0.0 (macOS, Windows) and 1.0.1 (Linux),
// iOS SDK 1.0.1, Android AARs 1.0.0, web 1.0.1. Paths are from the
// repository root. Check a finding again before building on it.
//
// No package captures runtime logs, and none has a log stream, callback or
// level option. The only runtime text that reaches Dart is the message of a
// failed call, as TaskException:
// - desktop and iOS: the C API's error string (checkedCall in
//   packages/mediapipe-task-vision/lib/src/io/native_vision_image.dart;
//   SdkError in packages/mediapipe-core/native/ios/sdk_bridge_support.h);
// - Android: the Java exception's toString() (TaskHost.java);
// - web: the JS error's message, posted by each family's assets/worker.js.
// Warnings and info lines never arrive.
//
// Where the lines go instead, and what could capture them:
//
// - macOS, Linux, Windows: the process's stderr, from two writers. MediaPipe
//   logs through absl ("W0000 00:00:<epoch> <thread> file.cc:NN] text").
//   TensorFlow Lite prints its own lines, without absl's prefix ("INFO:
//   Created TensorFlow Lite XNNPACK delegate for CPU."). Samples: the
//   inference-release.log files under packages/mediapipe-task-vision/tool/
//   validations/2026-09-18-desktop-cpu-gallery/.
//   Google's C API has no log function: none of the 128 Mp* exports of its
//   macOS library. That library does export C++ symbols, with no inline
//   namespace (nm -gU | c++filt): absl::log_internal::AddLogSink and
//   RemoveLogSink, absl::SetMinLogLevel, absl::SetStderrThreshold and
//   tflite::LoggerOptions::SetMinimumLogSeverity. A sink needs a C++ shim
//   whose absl::LogSink and absl::LogEntry match Google's build, which
//   nothing guarantees, and it would likely still miss TensorFlow Lite's
//   lines. The Linux and Windows libraries were not inspected; a Windows
//   DLL exports only what it declares.
//   Redirecting file descriptor 2 into a pipe needs no symbols and catches
//   both writers and every library, but it is process-wide, and a reader
//   that falls behind blocks the threads that log. Not tried.
// - iOS: stderr and the system log. Google's MediaPipeTaskGraphs_library.a
//   imports fprintf, vfprintf, vsyslog, NSLog and os_log_create, and defines
//   the same absl and tflite symbols. Core's hook links that archive into
//   its own mediapipe_ios framework, with the bridges in
//   packages/mediapipe-core/native/ios/*.mm, so a bridge could register a
//   sink, with the same caveat about absl's layout.
// - Android: logcat. Google's libmediapipe_tasks_jni.so imports
//   __android_log_print, __android_log_vprint and __android_log_write, and
//   exports only its JNI entry points, so there is no sink to register. An
//   app's stderr reaches nothing. That leaves reading the app's own logcat
//   from the plugin (logcat --pid), which was not tried. Google's Java API
//   was not searched for a log callback.
// - Web: the worker's console. Google's Emscripten loader
//   (wasm/*_wasm_internal.js) sends stdout to console.log and stderr to
//   console.error unless Module.print and Module.printErr are set, and the
//   bundle passes self.Module to its module factory (read in the vision
//   bundle only). Vision's assets/worker.js already sets self.Module around
//   createFromOptions, for instantiateWasm; text's and audio's do not. The
//   lines need a worker message of their own: vision's bridge.js and core's
//   task_bridge.js drop a message whose id has no pending request. The
//   bundle's few direct console.warn and console.error calls bypass both
//   hooks.
//
// Also:
//
// - Where vision's source-built face runtimes are used
//   (packages/mediapipe-task-vision/hook/build.dart), they are separate
//   libraries: a sink registered in core's engine would not see their lines.
// - Google logs from its own threads (the thread ids in the samples differ),
//   and the FFI tasks run in worker isolates (vision_task_worker.dart,
//   text_task_worker.dart). A native callback into Dart has to be callable
//   from any thread (NativeCallable.listener) and own a copy of the text.
// - The packages' own diagnostics bypass Dart too: MPTRACE lines on stderr
//   (MEDIAPIPE_VISION_TRACE=1, vision_task_worker.dart), one Log.i in
//   MediaPipeVisionPlugin.java and one console.warn in vision's worker.js.
//   The package:logging records in src/legacy and mediapipe_genai are Dart
//   messages, not Google's.
// - Google's "usage logging" is something else: the telemetry upload of
//   upstream-issues.md UP-025 (MpBaseOptions.ca_bundle_path).
