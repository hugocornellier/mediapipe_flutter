/// Versioned official Hand Landmarker float16 task bundle.
const handLandmarkerUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

/// SHA-256 of [handLandmarkerUrl].
const handLandmarkerSha256 =
    'fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1';

/// Versioned official Gesture Recognizer float16 task bundle.
const gestureRecognizerUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task';

/// SHA-256 of [gestureRecognizerUrl].
const gestureRecognizerSha256 =
    '97952348cf6a6a4915c2ea1496b4b37ebabc50cbbf80571435643c455f2b0482';

/// Versioned official Pose Landmarker Lite float16 task bundle.
const poseLandmarkerLiteUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task';

/// SHA-256 of [poseLandmarkerLiteUrl].
const poseLandmarkerLiteSha256 =
    '59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a';

/// Versioned official Holistic Landmarker float16 task bundle.
const holisticLandmarkerUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'holistic_landmarker/holistic_landmarker/float16/1/holistic_landmarker.task';

/// SHA-256 of [holisticLandmarkerUrl].
const holisticLandmarkerSha256 =
    'e2dab61191e2dcd0a15f943d8e3ed1dce13c82dfa597b9dd39f562975a50c3f8';

/// Official, unmodified BlazeFace short-range float16 model, version 1.
const blazeFaceShortRangeUrl =
    'https://storage.googleapis.com/mediapipe-models/face_detector/'
    'blaze_face_short_range/float16/1/blaze_face_short_range.tflite';

/// SHA-256 of [blazeFaceShortRangeUrl].
const blazeFaceShortRangeSha256 =
    'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f';

/// Official Face Landmarker float16 bundle, version 1 (FaceMesh V2).
/// Contains the face detector, 478-landmark model, and blendshape model.
const faceLandmarkerUrl =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/'
    'face_landmarker/float16/1/face_landmarker.task';

/// SHA-256 of [faceLandmarkerUrl].
const faceLandmarkerSha256 =
    '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff';

/// Official EfficientDet-Lite0 float32 detector, version 1, 80 COCO classes.
///
/// Float32 rather than int8 because Metal needs a float model; see
/// tool/GPU_VALIDATION.md.
const efficientDetLite0Url =
    'https://storage.googleapis.com/mediapipe-models/object_detector/'
    'efficientdet_lite0/float32/1/efficientdet_lite0.tflite';

/// SHA-256 of [efficientDetLite0Url].
const efficientDetLite0Sha256 =
    '40338edf5ec70d43e318b0a716a84d4564cd1802759a7a07170c7e43796dbf58';

/// Official ImageNet EfficientNet-Lite0 float32 classifier, version 1.
const efficientNetLite0Url =
    'https://storage.googleapis.com/mediapipe-models/image_classifier/'
    'efficientnet_lite0/float32/1/efficientnet_lite0.tflite';

/// SHA-256 of [efficientNetLite0Url].
const efficientNetLite0Sha256 =
    '6c7ab0a6e5dcbf38a8c33b960996a55a3b4300b36a018c4545801de3a3c8bde0';

/// Official MobileNet-V3 small float32 image embedder, version 1.
const mobileNetV3SmallUrl =
    'https://storage.googleapis.com/mediapipe-models/image_embedder/'
    'mobilenet_v3_small/float32/1/mobilenet_v3_small.tflite';

/// SHA-256 of [mobileNetV3SmallUrl].
const mobileNetV3SmallSha256 =
    'bbbb4c51a55a53905af1daec995ca1aae355046f8839bb8c9f5ce9271394bc40';

/// Official stateful MagicTouch int8 encoder/decoder bundle, version 1.
const interactiveSegmenterModelUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task';

/// SHA-256 of [interactiveSegmenterModelUrl].
const interactiveSegmenterModelSha256 =
    '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03';
