import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'text_task_worker.dart';
import 'third_party/mediapipe/classic_text_bindings.dart' as mp;

/// Where core's shared runtime serves these tasks: Google's macOS 1.0.1
/// library, its Linux 1.0.1 and Windows 1.0.0 wheel libraries, and its iOS
/// 1.0.1 SDK through the adapter mediapipe_core builds.
const _runtimeAbis = {
  Abi.macosArm64,
  Abi.linuxX64,
  Abi.windowsX64,
  Abi.iosArm64,
};

/// Validate availability before starting a worker or resolving inference calls.
void requireTextTasksRuntime() {
  if (!_runtimeAbis.contains(Abi.current())) {
    throw const RuntimeUnavailableException(
      'Classic text runtime unavailable on this platform.',
      fix:
          'Use macOS arm64, Linux x64, Windows x64 or iOS arm64, or install '
          'the browser or Android platform plugin.',
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
      'Classic text runtime unavailable.',
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
    target.modelAssetPath = options.modelPath!
        .toNativeUtf8(allocator: arena)
        .cast();
  }
}

/// Allocate all nested strings in the same short-lived arena.
void fillTextClassifierOptions(
  mp.MpClassifierOptions target,
  Arena arena, {
  required String? displayNamesLocale,
  required int maxResults,
  required double scoreThreshold,
  required List<String> categoryAllowlist,
  required List<String> categoryDenylist,
}) {
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
        displayNamesLocale?.toNativeUtf8(allocator: arena).cast() ?? nullptr
    ..maxResults = maxResults
    ..scoreThreshold = scoreThreshold
    ..categoryAllowlist = strings(categoryAllowlist)
    ..categoryAllowlistCount = categoryAllowlist.length
    ..categoryDenylist = strings(categoryDenylist)
    ..categoryDenylistCount = categoryDenylist.length;
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

  /// Close synchronously when using an executor directly.
  void dispose() => close();
}
