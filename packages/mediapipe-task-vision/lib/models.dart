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

/// Official stateful MagicTouch int8 encoder/decoder bundle, version 1.
const interactiveSegmenterModelUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task';

/// SHA-256 of [interactiveSegmenterModelUrl].
const interactiveSegmenterModelSha256 =
    '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03';
