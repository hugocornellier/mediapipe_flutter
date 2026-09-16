/// Shared native plumbing for every task served by the combined runtime.
///
/// The two face tasks keep their own copies while their own per-task libraries
/// are published: each generated binding set declares its own `MpImageFormat`
/// and `MpImagePtr`, so the Dart types do not interchange even though the ABI
/// is identical.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/vision_types.dart';
import 'pixel_conversion.dart';

/// Builds a native image from [input], copying pixels into [arena].
///
/// Set [expandRgbForGpu] when the task runs on Metal: Apple's GPU image upload
/// cannot accept three-channel ImageFrames, so opaque alpha is added before
/// entering the official graph.
mp.MpImagePtr createVisionImage(
  Arena arena,
  VisionImage input, {
  required bool expandRgbForGpu,
  required void Function(mp.MpStatus Function(Pointer<Pointer<Char>>)) checked,
}) {
  final imageOut = arena<mp.MpImagePtr>();
  if (input.path case final path?) {
    final name = path.toNativeUtf8(allocator: arena).cast<Char>();
    checked((error) => mp.MpImageCreateFromFile(name, imageOut, error));
    return imageOut.value;
  }
  final bytes = input.pixels!;
  final expandRgb = expandRgbForGpu && input.format == VisionPixelFormat.rgb;
  final rowSize = input.width! * (expandRgb ? 4 : input.format!.channels);
  final byteCount = rowSize * input.height!;
  final pixels = arena<Uint8>(byteCount);
  final packed = pixels.asTypedList(byteCount);
  if (expandRgb) {
    for (var y = 0; y < input.height!; y++) {
      for (var x = 0; x < input.width!; x++) {
        final source = y * input.bytesPerRow! + x * 3;
        final target = y * rowSize + x * 4;
        packed[target] = bytes[source];
        packed[target + 1] = bytes[source + 1];
        packed[target + 2] = bytes[source + 2];
        packed[target + 3] = 255;
      }
    }
  } else if (input.format == VisionPixelFormat.bgra) {
    copyBgraToRgba(
      source: bytes,
      target: packed,
      width: input.width!,
      height: input.height!,
      bytesPerRow: input.bytesPerRow!,
    );
  } else {
    for (var y = 0; y < input.height!; y++) {
      packed.setRange(
        y * rowSize,
        (y + 1) * rowSize,
        bytes,
        y * input.bytesPerRow!,
      );
    }
  }
  checked(
    (error) => mp.MpImageCreateFromUint8Data(
      input.format == VisionPixelFormat.rgb && !expandRgb
          ? mp.MpImageFormat.kMpImageFormatSrgb
          : mp.MpImageFormat.kMpImageFormatSrgba,
      input.width!,
      input.height!,
      pixels,
      byteCount,
      imageOut,
      error,
    ),
  );
  return imageOut.value;
}

/// Calls [call] and turns a non-OK status into an exception from [onError].
///
/// The native message is freed on every path, including when [onError] throws.
void checkedCall(
  mp.MpStatus Function(Pointer<Pointer<Char>>) call, {
  required Object Function(String message, int statusCode) onError,
}) {
  final error = calloc<Pointer<Char>>();
  try {
    final status = call(error);
    if (status != mp.MpStatus.kMpOk) {
      throw onError(
        nativeString(error.value) ?? 'MediaPipe returned ${status.name}',
        status.value,
      );
    }
  } finally {
    if (error.value != nullptr) mp.MpErrorFree(error.value);
    calloc.free(error);
  }
}

/// Copies a native string, treating an empty one as absent.
String? nativeString(Pointer<Char> pointer) {
  if (pointer == nullptr) return null;
  final value = pointer.cast<Utf8>().toDartString();
  // The official Python API treats empty optional C strings as absent.
  return value.isEmpty ? null : value;
}
