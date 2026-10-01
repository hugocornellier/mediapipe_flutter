import 'dart:io';

import 'package:mediapipe_core/capabilities.dart' show TaskCapabilities;

import '../capabilities/require_delegate.dart';
import '../sdk_vision_task.dart';
import '../vision_task_backend.dart';
import 'vision_task_worker.dart';

/// Where one vision task runs: a registered Android SDK adapter, or elsewhere
/// Google's native runtime on a worker isolate. Each task class forwards here.
final class VisionTaskRunner<R> {
  VisionTaskRunner._(this._sdk, this._worker);
  final SdkVisionTask<R>? _sdk;
  final VisionTaskWorker<R>? _worker;

  /// Mode selected when creating the task.
  RunningMode get runningMode => _sdk?.runningMode ?? _worker!.runningMode;

  /// Prepare the model, then run the task through [android] when that adapter
  /// is registered on Android. Elsewhere check [capabilities] for the
  /// requested delegate, run [validate], and open [native] on a worker isolate
  /// named [debugName]. [name] appears in the adapter's errors.
  static Future<VisionTaskRunner<R>> open<R, O extends VisionModelOptions>(
    O options, {
    required String name,
    required String debugName,
    required Future<VisionTaskBackend<R>> Function(O)? android,
    required NativeVisionTask<R> Function(O) native,
    Future<TaskCapabilities<VisionDelegate>> Function()? capabilities,
    void Function()? validate,
  }) async {
    await options.prepareModel();
    if (Platform.isAndroid && android != null) {
      return VisionTaskRunner._(
        SdkVisionTask(
          await android(options),
          options.runningMode,
          options.delegate,
          name: name,
          // MediaPipe converts milliseconds to signed 64-bit microseconds.
          maxTimestamp: 0x7fffffffffffffff ~/ 1000,
        ),
        null,
      );
    }
    if (capabilities != null) {
      requireVisionDelegate(await capabilities(), options.delegate);
    }
    validate?.call();
    return VisionTaskRunner._(
      null,
      await VisionTaskWorker.create(options, native, debugName),
    );
  }

  /// IMAGE inference; [regionOfInterest] applies only to tasks that accept one.
  Future<R> image(
    VisionImage image,
    int rotationDegrees, {
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.detectImage(
        image,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _worker!.processImage(image, rotationDegrees, regionOfInterest);

  /// VIDEO inference with a strictly increasing millisecond timestamp.
  Future<R> video(
    VisionImage image,
    int rotationDegrees,
    int timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.detectForVideo(
        image,
        timestampMilliseconds: timestampMilliseconds,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _worker!.processVideo(
        image,
        rotationDegrees,
        timestampMilliseconds,
        regionOfInterest,
      );

  /// Drain queued requests and release the task exactly once.
  Future<void> dispose() => _sdk?.dispose() ?? _worker!.dispose();
}
