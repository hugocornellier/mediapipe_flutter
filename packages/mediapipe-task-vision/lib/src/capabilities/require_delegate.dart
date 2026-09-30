import 'package:mediapipe_core/capabilities.dart' show TaskCapabilities;
import 'package:mediapipe_core/mediapipe_exception.dart';

import '../interface/vision_types.dart';

/// Fails with actionable setup text when a delegate is unavailable.
void requireVisionDelegate(
  TaskCapabilities<VisionDelegate> capabilities,
  VisionDelegate delegate,
) {
  if (capabilities.supportedDelegates.contains(delegate)) return;
  throw RuntimeUnavailableException(
    'Vision delegate $delegate is unavailable on this platform.',
    fix:
        capabilities.unavailableReasons[delegate] ??
        'Choose a supported delegate returned by this task capability query.',
  );
}
