import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/interactive_segmenter_bindings.dart' as mp;
import '../../third_party/mediapipe/interactive_segmenter_wheel_bindings.dart'
    as wheel;
import '../interface/interactive_segmenter_types.dart';
import '../interface/vision_types.dart';
import 'pixel_conversion.dart';

/// One Interactive Segmenter session, owned by its persistent worker isolate:
/// Google's desktop 1.0.1 runtime, or its iOS SDK through the vision adapter.
abstract interface class InteractiveSegmenterSession {
  /// Replace the image, resetting the stroke session.
  void setImage(VisionImage input);

  /// Submit the full stroke history and copy the returned confidence mask.
  SegmentationMask segment(List<SegmentationStroke> strokes);

  /// Release the task and its image exactly once.
  void close();
}

/// Google's stateful C API: core's shared 1.0.1 runtime on macOS, and on Linux
/// the vision package's own 1.0.1 wheel library, which exports the same API.
final class _Api {
  const _Api({
    required this.create,
    required this.setImage,
    required this.segment,
    required this.close,
    required this.imageFromFile,
    required this.imageFromPixels,
    required this.imageData,
    required this.imageWidth,
    required this.imageHeight,
    required this.imageChannels,
    required this.imageByteDepth,
    required this.imageFree,
    required this.errorFree,
  });

  final int Function(
    Pointer<mp.MpInteractiveSegmenterOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
  create;
  final int Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Char>>)
  setImage;
  final int Function(
    Pointer<Void>,
    Pointer<mp.MpStrokes>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
  segment;
  final int Function(Pointer<Void>, Pointer<Pointer<Char>>) close;
  final int Function(
    Pointer<Char>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
  imageFromFile;
  final int Function(
    int,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
  imageFromPixels;
  final int Function(
    Pointer<Void>,
    Pointer<Pointer<Float>>,
    Pointer<Pointer<Char>>,
  )
  imageData;
  final int Function(Pointer<Void>) imageWidth;
  final int Function(Pointer<Void>) imageHeight;
  final int Function(Pointer<Void>) imageChannels;
  final int Function(Pointer<Void>) imageByteDepth;
  final void Function(Pointer<Void>) imageFree;
  final void Function(Pointer<Char>) errorFree;
}

final _api = Platform.isLinux
    ? const _Api(
        create: wheel.create,
        setImage: wheel.setImage,
        segment: wheel.segment,
        close: wheel.close,
        imageFromFile: wheel.imageFromFile,
        imageFromPixels: wheel.imageFromPixels,
        imageData: wheel.imageData,
        imageWidth: wheel.imageWidth,
        imageHeight: wheel.imageHeight,
        imageChannels: wheel.imageChannels,
        imageByteDepth: wheel.imageByteDepth,
        imageFree: wheel.imageFree,
        errorFree: wheel.errorFree,
      )
    : const _Api(
        create: mp.create,
        setImage: mp.setImage,
        segment: mp.segment,
        close: mp.close,
        imageFromFile: mp.imageFromFile,
        imageFromPixels: mp.imageFromPixels,
        imageData: mp.imageData,
        imageWidth: mp.imageWidth,
        imageHeight: mp.imageHeight,
        imageChannels: mp.imageChannels,
        imageByteDepth: mp.imageByteDepth,
        imageFree: mp.imageFree,
        errorFree: mp.errorFree,
      );

/// Synchronous native owner; used only by its persistent worker isolate.
final class NativeInteractiveSegmenter implements InteractiveSegmenterSession {
  /// Create the official CPU task and acquire its native handle.
  NativeInteractiveSegmenter(InteractiveSegmenterOptions options) {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError(
        'Interactive Segmenter supports macOS arm64 and Linux x64 here.',
      );
    }
    if (options.delegate != VisionDelegate.cpu) {
      throw UnsupportedError(
        'Interactive Segmenter supports CPU only. The official macOS runtime '
        'cannot initialize its GPU stroke shader, and Linux GPU is not '
        'validated for this task.',
      );
    }
    using((arena) {
      final native = arena<mp.MpInteractiveSegmenterOptions>();
      native.ref.baseOptions
        ..fileDescriptor = -1
        ..delegate = 0
        ..hostSystem = 2;
      if (options.modelPath case final path?) {
        native.ref.baseOptions.modelAssetPath = path
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      if (options.modelBytes case final bytes?) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        native.ref.baseOptions
          ..modelAssetBuffer = buffer.cast()
          ..modelAssetBufferCount = bytes.length;
      }
      final output = arena<Pointer<Void>>();
      _checked((error) => _api.create(native, output, error));
      _task = output.value;
    });
  }

  Pointer<Void> _task = nullptr;
  Pointer<Void> _image = nullptr;
  bool _hasImage = false;

  /// Replace the image, retaining native input ownership until replacement.
  @override
  void setImage(VisionImage input) {
    final next = _createImage(input);
    try {
      _hasImage = false;
      _checked((error) => _api.setImage(_task, next, error));
    } catch (_) {
      _api.imageFree(next);
      rethrow;
    }
    if (_image != nullptr) _api.imageFree(_image);
    _image = next;
    _hasImage = true;
  }

  /// Submit the full history and copy the returned confidence mask.
  @override
  SegmentationMask segment(List<SegmentationStroke> strokes) {
    if (!_hasImage) {
      throw StateError('Call setImage successfully before segment.');
    }
    return using((arena) {
      final native = arena<mp.MpStrokes>();
      final values = arena<mp.MpStroke>(strokes.length);
      native.ref
        ..strokes = values
        ..strokesCount = strokes.length;
      for (var i = 0; i < strokes.length; i++) {
        final stroke = strokes[i];
        final points = arena<mp.MpStrokePoint>(stroke.points.length);
        for (var j = 0; j < stroke.points.length; j++) {
          points[j]
            ..x = stroke.points[j].x
            ..y = stroke.points[j].y;
        }
        values[i]
          ..brushMode = stroke.brushMode.nativeValue
          ..points = points
          ..pointsCount = stroke.points.length
          ..isCompleted = stroke.isCompleted;
      }
      final output = arena<Pointer<Void>>();
      try {
        _checked((error) => _api.segment(_task, native, output, error));
        final mask = output.value;
        if (mask == nullptr) throw StateError('MediaPipe returned no mask.');
        final width = _api.imageWidth(mask);
        final height = _api.imageHeight(mask);
        if (width <= 0 ||
            height <= 0 ||
            _api.imageChannels(mask) != 1 ||
            _api.imageByteDepth(mask) != 4) {
          throw StateError(
            'MediaPipe returned an invalid float32 confidence mask.',
          );
        }
        final data = arena<Pointer<Float>>();
        // The official accessor realigns noncontiguous data, just as numpy_view
        // does. Do not assume ImageFrame row alignment or expose native pointers.
        _checked((error) => _api.imageData(mask, data, error));
        if (data.value == nullptr) {
          throw StateError('MediaPipe returned no mask data.');
        }
        return SegmentationMask(
          width: width,
          height: height,
          confidence: data.value.asTypedList(width * height),
        );
      } catch (_) {
        // A native graph failure can persist. Require a fresh successful image
        // before accepting more segmentation; argument errors never reach here.
        _hasImage = false;
        rethrow;
      } finally {
        if (output.value != nullptr) _api.imageFree(output.value);
      }
    });
  }

  /// Release the task and retained image exactly once.
  @override
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    _hasImage = false;
    try {
      _checked((error) => _api.close(task, error));
    } finally {
      if (_image != nullptr) _api.imageFree(_image);
      _image = nullptr;
    }
  }
}

Pointer<Void> _createImage(VisionImage input) => using((arena) {
  final output = arena<Pointer<Void>>();
  try {
    if (input.path case final path?) {
      final name = path.toNativeUtf8(allocator: arena).cast<Char>();
      _checked((error) => _api.imageFromFile(name, output, error));
    } else {
      final width = input.width!;
      final height = input.height!;
      final row = width * input.format!.channels;
      final pixels = arena<Uint8>(row * height);
      final packed = pixels.asTypedList(row * height);
      if (input.format == VisionPixelFormat.bgra) {
        copyBgraToRgba(
          source: input.pixels!,
          target: packed,
          width: width,
          height: height,
          bytesPerRow: input.bytesPerRow!,
        );
      } else {
        for (var y = 0; y < height; y++) {
          packed.setRange(
            y * row,
            (y + 1) * row,
            input.pixels!,
            y * input.bytesPerRow!,
          );
        }
      }
      _checked(
        (error) => _api.imageFromPixels(
          input.format == VisionPixelFormat.rgb ? 1 : 2,
          width,
          height,
          pixels,
          row * height,
          output,
          error,
        ),
      );
    }
    return output.value;
  } catch (_) {
    if (output.value != nullptr) _api.imageFree(output.value);
    rethrow;
  }
});

void _checked(int Function(Pointer<Pointer<Char>>) call) {
  final error = calloc<Pointer<Char>>();
  try {
    final status = call(error);
    if (status != 0) {
      throw InteractiveSegmenterException(
        error.value == nullptr
            ? 'MediaPipe returned status $status.'
            : error.value.cast<Utf8>().toDartString(),
        statusCode: status,
      );
    }
  } finally {
    if (error.value != nullptr) _api.errorFree(error.value);
    calloc.free(error);
  }
}
