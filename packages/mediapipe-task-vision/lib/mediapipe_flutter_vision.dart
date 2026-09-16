// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Package containing MediaPipe's vision-specific tasks.
library;

export 'src/interface/landmark_task_types.dart'
    show
        VisionLandmark,
        HandLandmarkerOptions,
        HandLandmarkerResult,
        GestureClassifierOptions,
        GestureRecognizerOptions,
        GestureRecognizerResult,
        PoseLandmarkerOptions,
        PoseLandmarkerResult;
export 'src/interface/holistic_landmarker_types.dart';
export 'src/io/hand_landmarker.dart';
export 'src/io/gesture_recognizer.dart';
export 'src/io/pose_landmarker.dart';
export 'src/io/holistic_landmarker.dart';

export 'capabilities.dart';
export 'src/interface/face_detector_types.dart';
export 'src/io/face_detector.dart';
export 'src/interface/face_landmarker_types.dart';
export 'src/io/face_landmarker.dart';
export 'src/interface/face_landmark_connections.dart';
export 'src/interface/vision_types.dart';
export 'src/interface/interactive_segmenter_types.dart';
export 'src/io/interactive_segmenter.dart';
export 'src/interface/object_detector_types.dart';
export 'src/io/object_detector.dart';
export 'src/interface/image_classifier_types.dart';
export 'src/io/image_classifier.dart';
export 'src/interface/image_embedder_types.dart';
export 'src/io/image_embedder.dart';
