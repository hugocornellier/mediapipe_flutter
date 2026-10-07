import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'text_task_worker.dart';
import 'third_party/mediapipe/classic_text_bindings.dart' as mp;

/// This process's target, named as core's [tasksRuntimeTargets] names the
/// targets where Google's text library serves the text tasks, the
/// Proofreader and Summarizer included.
final _target =
    '${Platform.operatingSystem}/${Abi.current().toString().split('_').last}';

/// Validate availability before starting a worker or resolving inference calls.
void requireTextTasksRuntime() {
  if (!tasksRuntimeTargets.containsKey(_target)) {
    throw const RuntimeUnavailableException(
      "Google's text runtime is unavailable on this platform.",
      fix:
          'Use Android (arm64 or x64), iOS arm64, macOS arm64, Linux x64 or '
          'Windows x64, or a browser.',
    );
  }
  try {
    Native.addressOf<
      NativeFunction<
        Int32 Function(
          Pointer<mp.MpTextClassifierOptions>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Char>>,
        )
      >
    >(mp.classifierCreate);
  } catch (error) {
    if (missingLinuxGraphicsLibraries('$error') case final missing?) {
      throw missing;
    }
    throw RuntimeUnavailableException(
      "Google's text runtime is unavailable.",
      fix: tasksRuntimeUnavailable('this text task', Platform.operatingSystem),
    );
  }
}

/// Fill Google's base options from [options]' resolved model, always on
/// the CPU, which is all the classic text tasks run on.
void fillTextBaseOptions(
  mp.MpBaseOptions target,
  TaskOptions options,
  Arena arena,
) {
  target
    ..fileDescriptor = -1
    ..delegate = 0
    ..hostSystem = mpHostSystem;
  if (options.modelBytes case final bytes?) {
    final buffer = arena<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    target
      ..modelAssetBuffer = buffer.cast()
      ..modelAssetBufferCount = bytes.length;
  } else {
    target.modelAssetPath = nativeModelPath(
      options.modelPath!,
    ).toNativeUtf8(allocator: arena).cast();
  }
}

/// Allocate all nested strings in the same short-lived arena.
void fillTextClassifierOptions(
  mp.MpClassifierOptions target,
  Arena arena,
  ClassifierSettings settings,
) {
  Pointer<Pointer<Char>> strings(List<String> values) {
    if (values.isEmpty) return nullptr;
    final array = arena<Pointer<Char>>(values.length);
    for (var i = 0; i < values.length; i++) {
      array[i] = values[i].toNativeUtf8(allocator: arena).cast();
    }
    return array;
  }

  target
    ..displayNamesLocale =
        settings.displayNamesLocale?.toNativeUtf8(allocator: arena).cast() ??
        nullptr
    ..maxResults = settings.maxResults
    ..scoreThreshold = settings.scoreThreshold
    ..categoryAllowlist = strings(settings.categoryAllowlist)
    ..categoryAllowlistCount = settings.categoryAllowlist.length
    ..categoryDenylist = strings(settings.categoryDenylist)
    ..categoryDenylistCount = settings.categoryDenylist.length;
}

/// Copy an optional C string into Dart.
String? textTaskString(Pointer<Char> value) =>
    value == nullptr ? null : value.cast<Utf8>().toDartString();

/// Free Google's error string on both success and failure.
void checkTextStatus(int Function(Pointer<Pointer<Char>>) call) =>
    using((arena) {
      final error = arena<Pointer<Char>>();
      try {
        final status = call(error);
        if (status != 0) {
          throw TaskException(
            textTaskString(error.value) ?? 'MediaPipe operation failed.',
            statusCode: status,
          );
        }
      } finally {
        if (error.value != nullptr) mp.errorFree(error.value);
      }
    });

/// Synchronous native owner. Only its worker exposes asynchronous requests.
abstract class NativeClassicTextTask<I, R>
    implements NativeTextTask<I, R, Never> {
  /// Native handle, owned exclusively by this executor.
  Pointer<Void> handle = nullptr;

  /// Reject reuse and embedded NUL before reaching a native API.
  void checkInput(String text) {
    if (handle == nullptr) throw StateError('Text task has been disposed.');
    if (text.contains('\u0000')) {
      throw ArgumentError('Text must not contain NUL.');
    }
  }

  @override
  Future<void> stream(I input, void Function(Never) emit) =>
      throw UnsupportedError('This task has no native streaming API.');
}
