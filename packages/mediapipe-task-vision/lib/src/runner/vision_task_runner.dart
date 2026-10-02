/// Where one vision task runs: a registered platform SDK adapter (Google's
/// browser runtime or Android SDK), or Google's native runtime on a worker
/// isolate. Every task class forwards here, on every platform.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../types/vision_types.dart';
import '../vision_task_backend.dart';
import 'native_interface.dart';
import 'native_tasks.dart';
import 'sdk_vision_task.dart';

export 'native_interface.dart';

/// One task on whichever runtime serves it here.
final class VisionTaskRunner<R> {
  VisionTaskRunner._(this._sdk, this._native, this.runningMode);
  final SdkVisionTask<R>? _sdk;
  final NativeTaskRunner<R>? _native;

  /// The mode the task was created in.
  final RunningMode runningMode;

  /// Resolves the model, then opens the task: through [backend] where a
  /// platform plugin registered one (browsers, Android), else on Google's
  /// native runtime after [capabilities] admits the delegate and [validate]
  /// passes, with [native] creating the task on a worker named [debugName].
  /// [name] appears in errors.
  static Future<VisionTaskRunner<R>> open<R, O extends VisionTaskOptions>(
    O options, {
    required String name,
    required String debugName,
    required VisionBackendFactory<R, O>? backend,
    required NativeVisionTask<R> Function(O) native,
    Future<TaskCapabilities> Function()? capabilities,
    void Function()? validate,
  }) async {
    // TODO: Remove this rejection when LIVE_STREAM is split from VIDEO. See
    // RunningMode.liveStream.
    if (options.runningMode == RunningMode.liveStream) {
      throw UnsupportedError(
        'Live stream mode is not implemented by this runtime.',
      );
    }
    await resolveTaskModel(options);
    if (backend != null) {
      return VisionTaskRunner._(
        SdkVisionTask(await backend(options), options.runningMode, name: name),
        null,
        options.runningMode,
      );
    }
    if (capabilities != null) {
      requireDelegate(await capabilities(), options.delegate);
    }
    validate?.call();
    return VisionTaskRunner._(
      null,
      await openNativeTask(options, native, name, debugName),
      options.runningMode,
    );
  }

  /// The browser overlay behind this task, when its backend draws.
  VisionTaskOverlayBackend? get overlayBackend => _sdk?.overlayBackend;

  /// IMAGE inference; [regionOfInterest] only for the tasks that accept one.
  Future<R> image(
    VisionImage image,
    int rotationDegrees, {
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.image(
        image,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _native!.processImage(image, rotationDegrees, regionOfInterest);

  // TODO: Add LIVE_STREAM beside video() when it is split from VIDEO: a call
  // that returns at once and drops frames the way Google's runtime does,
  // before they are copied to the worker. See RunningMode.liveStream.
  /// VIDEO inference with a strictly increasing millisecond timestamp.
  Future<R> video(
    VisionImage image,
    int rotationDegrees,
    int timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.video(
        image,
        timestampMilliseconds: timestampMilliseconds,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _native!.processVideo(
        image,
        rotationDegrees,
        timestampMilliseconds,
        regionOfInterest,
      );

  /// Drains queued requests and releases the task exactly once.
  Future<void> dispose() => _sdk?.dispose() ?? _native!.dispose();
}
