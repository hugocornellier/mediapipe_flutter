import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/interactive_segmenter_bindings.dart'
    as strokes;
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/interactive_segmenter_types.dart';
import '../interface/vision_task_types.dart';
import 'native_interactive_segmenter.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';

const _asset = 'package:mediapipe_flutter_vision/vision.dylib';

@Native<
  Int32 Function(
    Pointer<mp.MpBaseOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpIosInteractiveSegmenterCreate', assetId: _asset)
external int _create(
  Pointer<mp.MpBaseOptions> base,
  Pointer<Pointer<Void>> task,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, mp.MpImagePtr, Pointer<Pointer<Char>>)>(
  symbol: 'MpIosInteractiveSegmenterSetImage',
  assetId: _asset,
)
external int _setImage(
  Pointer<Void> task,
  mp.MpImagePtr image,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<strokes.MpStrokes>,
    Pointer<mp.MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpIosInteractiveSegmenterSegment', assetId: _asset)
external int _segment(
  Pointer<Void> task,
  Pointer<strokes.MpStrokes> history,
  Pointer<mp.MpImagePtr> mask,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpIosInteractiveSegmenterClose',
  assetId: _asset,
)
external int _close(Pointer<Void> task, Pointer<Pointer<Char>> error);

/// Google's stateful MagicTouch segmenter through the official iOS SDK
/// adapter, owned by the Interactive Segmenter's worker isolate.
final class IosInteractiveSegmenter implements InteractiveSegmenterSession {
  /// Create the SDK task; CPU only, as the task's other runtimes.
  IosInteractiveSegmenter(InteractiveSegmenterOptions options) {
    if (options.delegate != VisionDelegate.cpu) {
      throw const InteractiveSegmenterException(
        'Interactive Segmenter supports CPU only.',
      );
    }
    using((arena) {
      final base = arena<mp.MpBaseOptions>();
      base.ref
        ..file_descriptor = -1
        ..delegate = mp.MpDelegate.MP_DELEGATE_CPU
        ..host_system = mp.MpHostSystem.MP_HOST_SYSTEM_IOS;
      if (options.modelPath case final path?) {
        base.ref.model_asset_path = path.toNativeUtf8(allocator: arena).cast();
      }
      if (options.modelBytes case final bytes?) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        base.ref
          ..model_asset_buffer = buffer.cast()
          ..model_asset_buffer_count = bytes.length;
      }
      final task = arena<Pointer<Void>>();
      _checked((error) => _create(base, task, error));
      _task = task.value;
    });
  }

  Pointer<Void> _task = nullptr;
  bool _hasImage = false;
  final IosBgraStorage? _storage = iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  @override
  void setImage(VisionImage input) => using((arena) {
    _hasImage = false;
    final image = createVisionImage(
      arena,
      input,
      expandRgbForGpu: false,
      checked: _checkedStatus,
      iosBgra: _storage,
    );
    try {
      _checked((error) => _setImage(_task, image, error));
      _hasImage = true;
    } finally {
      mp.MpImageFree(image);
    }
  });

  @override
  SegmentationMask segment(List<SegmentationStroke> history) {
    if (!_hasImage) {
      throw StateError('Call setImage successfully before segment.');
    }
    return using((arena) {
      final native = arena<strokes.MpStrokes>();
      final values = arena<strokes.MpStroke>(history.length);
      native.ref
        ..strokes = values
        ..strokesCount = history.length;
      for (final (i, stroke) in history.indexed) {
        final points = arena<strokes.MpStrokePoint>(stroke.points.length);
        for (final (j, point) in stroke.points.indexed) {
          points[j]
            ..x = point.x
            ..y = point.y;
        }
        values[i]
          ..brushMode = stroke.brushMode.nativeValue
          ..points = points
          ..pointsCount = stroke.points.length
          ..isCompleted = stroke.isCompleted;
      }
      final mask = arena<mp.MpImagePtr>();
      try {
        _checked((error) => _segment(_task, native, mask, error));
        return copyVisionConfidenceMask(arena, mask.value);
      } catch (_) {
        // As on the desktop runtime, a failure asks for a fresh image first.
        _hasImage = false;
        rethrow;
      } finally {
        if (mask.value != nullptr) mp.MpImageFree(mask.value);
      }
    });
  }

  @override
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    _hasImage = false;
    try {
      _checked((error) => _close(task, error));
    } finally {
      _storage?.close();
    }
  }
}

/// Reports a failed vision call as the Interactive Segmenter's exception.
void _checkedStatus(mp.MpStatus Function(Pointer<Pointer<Char>>) call) {
  try {
    checkVisionCall(call);
  } on VisionTaskException catch (error) {
    throw InteractiveSegmenterException(
      error.message,
      statusCode: error.statusCode,
    );
  }
}

void _checked(int Function(Pointer<Pointer<Char>>) call) =>
    _checkedStatus((error) => mp.MpStatus.fromValue(call(error)));
