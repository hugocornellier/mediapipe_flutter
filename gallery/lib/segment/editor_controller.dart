import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

abstract interface class SegmentationBackend {
  Future<void> setImage(VisionImage image);
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes);
  Future<void> dispose();
}

class NativeSegmentationBackend implements SegmentationBackend {
  NativeSegmentationBackend(this.task);
  final InteractiveSegmenter task;

  @override
  Future<void> setImage(VisionImage image) => task.setImage(image);
  @override
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) =>
      task.segment(strokes);
  @override
  Future<void> dispose() => task.dispose();
}

/// One active inference and one replaceable pending stroke snapshot.
///
/// Image changes, clear and undo invalidate obsolete results immediately.
/// MediaPipe always receives the complete history, including partial strokes.
class EditorController extends ChangeNotifier {
  EditorController(this._backend);
  final SegmentationBackend _backend;
  final _completed = <SegmentationStroke>[];
  List<SegmentationPoint>? _active;
  SegmentationBrushMode _activeBrush = SegmentationBrushMode.positive;
  SegmentationBrushMode brush = SegmentationBrushMode.positive;
  VisionImage? _input;
  SegmentationMask? mask;
  String? error;
  bool ready = false;
  bool _closed = false;
  int _generation = 0;
  int _revision = 0;
  ({int generation, int revision, List<SegmentationStroke> strokes})? _pending;
  Future<void>? _draining;
  Future<void>? _loading;
  Future<void>? _closing;
  double? lastInferenceMs;
  int completedRequests = 0;
  int coalescedRequests = 0;

  bool get busy => _draining != null;
  bool get canUndo => _completed.isNotEmpty || _active != null;
  List<SegmentationPoint> get activePoints => List.unmodifiable(_active ?? []);
  SegmentationBrushMode get activeBrush => _activeBrush;
  List<SegmentationStroke> get strokes => List.unmodifiable([
    ..._completed,
    if (_active case final points?
        when points.isNotEmpty &&
            (_activeBrush != SegmentationBrushMode.lasso || points.length >= 3))
      SegmentationStroke(
        brushMode: _activeBrush,
        points: points,
        isCompleted: false,
      ),
  ]);

  Future<void> loadImage(VisionImage image) {
    if (_closed) return Future.value();
    final generation = ++_generation;
    _revision++;
    _input = image;
    _pending = null;
    _completed.clear();
    _active = null;
    mask = null;
    error = null;
    lastInferenceMs = null;
    ready = false;
    _notify();
    return _loading = _load(image, generation);
  }

  Future<void> _load(VisionImage image, int generation) async {
    try {
      await _backend.setImage(image);
      if (!_closed && generation == _generation) ready = true;
    } catch (failure) {
      if (!_closed && generation == _generation) error = failure.toString();
    }
    _notify();
  }

  void begin(SegmentationPoint point) {
    if (!ready || _closed || _active != null) return;
    _activeBrush = brush;
    _active = [point];
    _changed();
  }

  void extend(SegmentationPoint point) {
    final points = _active;
    if (points == null || !ready || _closed) return;
    final previous = points.last;
    if (previous.x == point.x && previous.y == point.y) return;
    points.add(point);
    _changed();
  }

  void end() {
    final points = _active;
    if (points == null || _closed) return;
    if (_activeBrush != SegmentationBrushMode.lasso || points.length >= 3) {
      _completed.add(
        SegmentationStroke(
          brushMode: _activeBrush,
          points: [
            ...points,
            if (_activeBrush == SegmentationBrushMode.lasso) points.first,
          ],
        ),
      );
    }
    _active = null;
    _changed();
  }

  void undo() {
    if (!ready || !canUndo || _closed) return;
    if (_active != null) {
      _active = null;
    } else {
      _completed.removeLast();
    }
    if (_completed.isEmpty) {
      unawaited(clear());
    } else {
      _changed();
    }
  }

  Future<void> clear() async {
    if (_input case final image?) await loadImage(image);
  }

  void _changed() {
    _revision++;
    final history = strokes;
    if (history.isNotEmpty) {
      if (_pending != null) coalescedRequests++;
      _pending = (
        generation: _generation,
        revision: _revision,
        strokes: history,
      );
      _startDrain();
    } else {
      _pending = null;
    }
    _notify();
  }

  void _startDrain() {
    if (_draining == null && _pending != null && ready && !_closed) {
      _draining = _drain();
    }
  }

  Future<void> _drain() async {
    // Let _draining be assigned before a synchronously completing fake backend.
    await Future<void>.value();
    try {
      while (!_closed && ready && _pending != null) {
        final request = _pending!;
        _pending = null;
        final watch = Stopwatch()..start();
        try {
          final result = await _backend.segment(request.strokes);
          completedRequests++;
          if (!_closed &&
              request.generation == _generation &&
              request.revision == _revision) {
            mask = result;
            lastInferenceMs = watch.elapsedMicroseconds / 1000;
            error = null;
          }
        } catch (failure) {
          if (!_closed && request.generation == _generation) {
            ready = false;
            error = failure.toString();
            _pending = null;
          }
        }
        _notify();
      }
    } finally {
      _draining = null;
      _startDrain();
      _notify();
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> close() {
    _closed = true;
    ready = false;
    _generation++;
    _pending = null;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _loading;
    await _draining;
    await _backend.dispose();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
