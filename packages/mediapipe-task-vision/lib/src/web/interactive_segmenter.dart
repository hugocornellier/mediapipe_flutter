import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Google's stateful MagicTouch Interactive Segmenter on the official browser
/// runtime, installed by the web adapter: an image, then stroke histories.
final class InteractiveSegmenter {
  InteractiveSegmenter._(this._backend, this.delegate);
  final InteractiveSegmenterBackend _backend;
  Future<void>? _disposing;

  /// Requested inference backend, fixed at creation.
  final VisionDelegate delegate;

  /// Creates a task through the registered official browser adapter.
  static Future<InteractiveSegmenter> create(
    InteractiveSegmenterOptions options,
  ) async {
    // CPU or WebGL 2; the worker reports a browser without worker WebGL 2.
    return InteractiveSegmenter._(
      await requireBrowserFactory(interactiveSegmenterBackendFactory)(options),
      options.delegate,
    );
  }

  /// Replace the image and reset the stroke session, as on native platforms.
  Future<void> setImage(VisionImage image) {
    _checkOpen();
    return _backend.setImage(image);
  }

  /// Segment using the full current stroke history, as on native platforms.
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) {
    _checkOpen();
    if (strokes.isEmpty) throw ArgumentError('Supply at least one stroke.');
    return _backend.segment(List.unmodifiable(strokes));
  }

  void _checkOpen() {
    if (_disposing != null) {
      throw StateError('InteractiveSegmenter has been disposed.');
    }
  }

  /// Drain pending requests and close the task exactly once.
  Future<void> dispose() => _disposing ??= _backend.dispose();
}
