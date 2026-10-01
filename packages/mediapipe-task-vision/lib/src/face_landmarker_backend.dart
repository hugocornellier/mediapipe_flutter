/// Extension point for platform SDK adapters. Applications use FaceLandmarker.
library;

import 'interface/face_landmarker_types.dart';
import 'vision_task_backend.dart';

export 'vision_task_backend.dart';

/// A serialized, asynchronous adapter to an official platform SDK.
typedef FaceLandmarkerBackend = VisionTaskBackend<FaceLandmarkerResult>;

/// Installed by a platform plugin before the first task is created.
Future<FaceLandmarkerBackend> Function(FaceLandmarkerOptions)?
faceLandmarkerBackendFactory;
