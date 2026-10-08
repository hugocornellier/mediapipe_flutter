import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

import '../third_party/mediapipe/interactive_segmenter_bindings.dart' as seg;
import '../third_party/mediapipe/vision_bindings.dart' as mp;
import '../types/options.dart';
import '../types/strokes.dart';
import '../types/vision_types.dart';
import 'native_vision_image.dart' show createVisionImage;
import 'native_vision_task.dart'
    show checkVisionCall, copyVisionConfidenceMask, setVisionBaseOptions;

/// One Interactive Segmenter session, owned by its persistent worker isolate:
/// Google's vision library on Android, iOS, macOS and Linux.
abstract interface class InteractiveSegmenterSession {
  /// Replace the image, resetting the stroke session.
  void setImage(VisionImage input);

  /// Submit the full stroke history and copy the returned confidence mask.
  ConfidenceMask segment(List<Stroke> strokes);

  /// Release the task and its image exactly once.
  void close();
}

/// Synchronous native owner; used only by its persistent worker isolate.
final class NativeInteractiveSegmenter implements InteractiveSegmenterSession {
  /// Create the official CPU task and acquire its native handle.
  NativeInteractiveSegmenter(InteractiveSegmenterOptions options) {
    if (Platform.isWindows) {
      throw UnsupportedError(
        "Google's Windows library runs the Interactive Segmenter at about 25 "
        'seconds a stroke (upstream-issues.md UP-048), so the package does '
        'not offer it there.',
      );
    }
    if (options.delegate != Delegate.cpu) {
      throw UnsupportedError(
        'Interactive Segmenter supports CPU only. The official macOS runtime '
        'cannot initialize its GPU stroke shader, and Linux GPU is not '
        'validated for this task.',
      );
    }
    using((arena) {
      final native = arena<seg.MpInteractiveSegmenterOptions>();
      setVisionBaseOptions(arena, native.ref.base_options, options);
      final output = arena<Pointer<Void>>();
      _checked(
        (error) => seg.MpInteractiveSegmenterCreate(native, output, error),
      );
      _task = output.value;
    });
  }

  Pointer<Void> _task = nullptr;
  mp.MpImagePtr _image = nullptr;
  bool _hasImage = false;

  /// Replace the image, retaining native input ownership until replacement.
  @override
  void setImage(VisionImage input) {
    final next = using(
      (arena) => createVisionImage(
        arena,
        input,
        expandRgbForGpu: false,
        checked: checkVisionCall,
      ),
    );
    try {
      _hasImage = false;
      _checked(
        (error) => seg.MpInteractiveSegmenterSetImage(_task, next, error),
      );
    } catch (_) {
      mp.MpImageFree(next);
      rethrow;
    }
    if (_image != nullptr) mp.MpImageFree(_image);
    _image = next;
    _hasImage = true;
  }

  /// Submit the full history and copy the returned confidence mask.
  @override
  ConfidenceMask segment(List<Stroke> strokes) {
    if (!_hasImage) {
      throw StateError('Call setImage successfully before segment.');
    }
    return using((arena) {
      final native = arena<seg.MpStrokes>();
      final values = arena<seg.MpStroke>(strokes.length);
      native.ref
        ..strokes = values
        ..strokes_count = strokes.length;
      for (var i = 0; i < strokes.length; i++) {
        final stroke = strokes[i];
        final points = arena<seg.MpStrokePoint>(stroke.points.length);
        for (var j = 0; j < stroke.points.length; j++) {
          points[j]
            ..x = stroke.points[j].x
            ..y = stroke.points[j].y;
        }
        values[i]
          ..brush_mode = stroke.brushMode.nativeValue
          ..points = points
          ..points_count = stroke.points.length
          ..is_completed = stroke.isCompleted;
      }
      final output = arena<mp.MpImagePtr>();
      try {
        _checked(
          (error) =>
              seg.MpInteractiveSegmenterSegment(_task, native, output, error),
        );
        if (output.value == nullptr) {
          throw StateError('MediaPipe returned no mask.');
        }
        return copyVisionConfidenceMask(arena, output.value);
      } catch (_) {
        // A native graph failure can persist. Require a fresh successful image
        // before accepting more segmentation; argument errors never reach here.
        _hasImage = false;
        rethrow;
      } finally {
        if (output.value != nullptr) mp.MpImageFree(output.value);
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
      _checked((error) => seg.MpInteractiveSegmenterClose(task, error));
    } finally {
      if (_image != nullptr) mp.MpImageFree(_image);
      _image = nullptr;
    }
  }
}

/// The stateful API's bindings return the status code as an int.
void _checked(int Function(Pointer<Pointer<Char>>) call) =>
    checkVisionCall((error) => mp.MpStatus.fromValue(call(error)));
