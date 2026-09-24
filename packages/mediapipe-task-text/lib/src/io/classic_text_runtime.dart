import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_core/io.dart';

import '../interface/text_task_exception.dart';
import 'text_task_worker.dart';
import 'third_party/mediapipe/classic_text_bindings.dart' as mp;

/// Where core's shared runtime serves these tasks: Google's macOS 1.0.1
/// library, and its Linux 1.0.1 and Windows 1.0.0 wheel libraries.
const _runtimeAbis = {Abi.macosArm64, Abi.linuxX64, Abi.windowsX64};

/// Validate availability before starting a worker or resolving inference calls.
void requireTextTasksRuntime() {
  if (!_runtimeAbis.contains(Abi.current())) {
    throw UnsupportedError(
      'MediaPipe text tasks run on macOS arm64, Linux x64 and Windows x64 CPU '
      'here, and on the web, Android and iOS through their platform plugins.',
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
    throw UnsupportedError(
      'Enable mediapipe_flutter_core.tasks_runtime: true in the app pubspec hooks.user_defines to use MediaPipe text tasks.',
    );
  }
}

/// Snapshot the caller's model bytes; options never retain native allocations.
BaseOptions copyTextBaseOptions(BaseOptions value) {
  final path = value.modelAssetPath;
  final bytes = value.modelAssetBuffer;
  if (path != null) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        'modelAssetPath',
        'Expected a nonempty filesystem path without NUL.',
      );
    }
    return BaseOptions.path(path);
  }
  if (bytes == null || bytes.isEmpty || bytes.length > 0xffffffff) {
    throw ArgumentError('modelAssetBuffer must contain 1 to 2^32-1 bytes.');
  }
  return BaseOptions.memory(Uint8List.fromList(bytes).asUnmodifiableView());
}

/// Snapshot option lists and reject values that cannot be represented in C.
ClassifierOptions copyTextClassifierOptions(ClassifierOptions value) {
  for (final text in [
    value.displayNamesLocale,
    ...?value.categoryAllowlist,
    ...?value.categoryDenylist,
  ]) {
    if (text?.contains('\u0000') ?? false) {
      throw ArgumentError('Classifier strings must not contain NUL.');
    }
  }
  if (value.maxResults != null &&
      (value.maxResults! < -0x80000000 || value.maxResults! > 0x7fffffff)) {
    throw ArgumentError.value(
      value.maxResults,
      'maxResults',
      'Must fit int32.',
    );
  }
  if (value.scoreThreshold != null && !value.scoreThreshold!.isFinite) {
    throw ArgumentError.value(
      value.scoreThreshold,
      'scoreThreshold',
      'Must be finite.',
    );
  }
  return ClassifierOptions(
    displayNamesLocale: value.displayNamesLocale,
    maxResults: value.maxResults,
    scoreThreshold: value.scoreThreshold,
    categoryAllowlist: value.categoryAllowlist == null
        ? null
        : List.unmodifiable(value.categoryAllowlist!),
    categoryDenylist: value.categoryDenylist == null
        ? null
        : List.unmodifiable(value.categoryDenylist!),
  );
}

/// Fill the current base ABI without using the inherited 2024 structs.
void fillTextBaseOptions(
  mp.MpBaseOptions target,
  BaseOptions source,
  Arena arena,
) {
  target
    ..fileDescriptor = -1
    ..delegate = 0
    ..hostSystem = mpHostSystem;
  if (source.modelAssetPath case final path?) {
    target.modelAssetPath = path.toNativeUtf8(allocator: arena).cast();
  } else {
    final bytes = source.modelAssetBuffer!;
    final buffer = arena<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    target
      ..modelAssetBuffer = buffer.cast()
      ..modelAssetBufferCount = bytes.length;
  }
}

/// Allocate all nested strings in the same short-lived arena.
void fillTextClassifierOptions(
  mp.MpClassifierOptions target,
  ClassifierOptions source,
  Arena arena,
) {
  Pointer<Pointer<Char>> strings(List<String>? values) {
    if (values == null || values.isEmpty) return nullptr;
    final array = arena<Pointer<Char>>(values.length);
    for (var i = 0; i < values.length; i++) {
      array[i] = values[i].toNativeUtf8(allocator: arena).cast();
    }
    return array;
  }

  target
    ..displayNamesLocale =
        source.displayNamesLocale?.toNativeUtf8(allocator: arena).cast() ??
        nullptr
    ..maxResults = source.maxResults ?? -1
    ..scoreThreshold = source.scoreThreshold ?? 0
    ..categoryAllowlist = strings(source.categoryAllowlist)
    ..categoryAllowlistCount = source.categoryAllowlist?.length ?? 0
    ..categoryDenylist = strings(source.categoryDenylist)
    ..categoryDenylistCount = source.categoryDenylist?.length ?? 0;
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
          throw TextTaskException(
            textTaskString(error.value) ?? 'MediaPipe operation failed.',
            status: status,
          );
        }
      } finally {
        if (error.value != nullptr) mp.errorFree(error.value);
      }
    });

/// Synchronous native owner. Only its worker exposes asynchronous requests.
abstract class NativeClassicTextTask<R> implements NativeTextTask<R, Never> {
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
  Future<void> stream(String text, void Function(Never) emit) =>
      throw UnsupportedError('This task has no native streaming API.');

  /// Close synchronously when using an executor directly.
  void dispose() => close();
}
