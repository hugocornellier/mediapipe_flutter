/// The models, samples and task lists the Android and macOS galleries bundle.
///
/// Every URL and SHA-256 here must equal the pin in the owning package's
/// `lib/models.dart`, and the macOS task list must match the vision package's
/// `sdk_downloads.dart`; `test/pins_test.dart` and `test/targets_test.dart`
/// check that, since this tool cannot import those Flutter packages.
library;

final class Model {
  const Model(this.fileName, this.url, this.sha256);

  final String fileName;
  final String url;
  final String sha256;
}

/// The model the gallery uses for every task some target bundles.
const models = <String, Model>{
  'audio_classifier': Model(
    'yamnet.tflite',
    'https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite',
    '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf',
  ),
  'embedding_gemma': Model(
    'embedding_gemma.task',
    'https://storage.googleapis.com/mediapipe-models/text_embedder/embedding_gemma/int4int8/1/embedding_gemma.task',
    '913b7a1edc7c7c3d1da3979ec1d0648ed9e0a370f181bb59ab177ca4b97707ad',
  ),
  'face_detector': Model(
    'blaze_face_short_range.tflite',
    'https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite',
    'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f',
  ),
  'face_landmarker': Model(
    'face_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task',
    '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff',
  ),
  'gesture_recognizer': Model(
    'gesture_recognizer.task',
    'https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task',
    '97952348cf6a6a4915c2ea1496b4b37ebabc50cbbf80571435643c455f2b0482',
  ),
  'hand_landmarker': Model(
    'hand_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task',
    'fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1',
  ),
  'holistic_landmarker': Model(
    'holistic_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/holistic_landmarker/holistic_landmarker/float16/1/holistic_landmarker.task',
    'e2dab61191e2dcd0a15f943d8e3ed1dce13c82dfa597b9dd39f562975a50c3f8',
  ),
  'image_classifier': Model(
    'efficientnet_lite0.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_classifier/efficientnet_lite0/float32/1/efficientnet_lite0.tflite',
    '6c7ab0a6e5dcbf38a8c33b960996a55a3b4300b36a018c4545801de3a3c8bde0',
  ),
  'image_embedder': Model(
    'mobilenet_v3_small.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_embedder/mobilenet_v3_small/float32/1/mobilenet_v3_small.tflite',
    'bbbb4c51a55a53905af1daec995ca1aae355046f8839bb8c9f5ce9271394bc40',
  ),
  'image_segmenter': Model(
    'deeplab_v3.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_segmenter/deeplab_v3/float32/1/deeplab_v3.tflite',
    'ff36e24d40547fe9e645e2f4e8745d1876d6e38b332d39a82f0bf0f5d1d561b3',
  ),
  'interactive_segmenter': Model(
    'interactive_segmentation.task',
    'https://storage.googleapis.com/mediapipe-models/interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task',
    '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03',
  ),
  'language_detector': Model(
    'language_detector.tflite',
    'https://storage.googleapis.com/mediapipe-models/language_detector/language_detector/float32/1/language_detector.tflite',
    '7db4f23dfe1ad8966b050b419a865da451143fd43eb6b606a256aadeeb1e5417',
  ),
  'object_detector': Model(
    'efficientdet_lite0.tflite',
    'https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float32/1/efficientdet_lite0.tflite',
    '40338edf5ec70d43e318b0a716a84d4564cd1802759a7a07170c7e43796dbf58',
  ),
  'pose_landmarker': Model(
    'pose_landmarker_lite.task',
    'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task',
    '59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a',
  ),
  'text_classifier': Model(
    'bert_classifier.tflite',
    'https://storage.googleapis.com/mediapipe-models/text_classifier/bert_classifier/float32/1/bert_classifier.tflite',
    '9b45012ab143d88d61e10ea501d6c8763f7202b86fa987711519d89bfa2a88b1',
  ),
  'text_embedder': Model(
    'universal_sentence_encoder.tflite',
    'https://storage.googleapis.com/mediapipe-models/text_embedder/universal_sentence_encoder/float32/1/universal_sentence_encoder.tflite',
    '89ad3c74175dd8caa398cc22b657296d94302d20c525c12b58b29420f7249749',
  ),
  'text_proofreader': Model(
    'proofread_quant_200m.litertlm',
    'https://storage.googleapis.com/mediapipe-models/text_proofreader/200m/1/proofread_quant_200m.litertlm',
    '2caa317d5a6f951af6e437edce3bb3a9fdedc85a7a8c2a8fcaec96318d7708cc',
  ),
  'text_summarizer': Model(
    'summarization_quant_200m_2modes.litertlm',
    'https://storage.googleapis.com/mediapipe-models/text_summarizer/200m/1/summarization_quant_200m_2modes.litertlm',
    '8b2d4ef09236adb9ead3127325526ba1aa5a59feb7c5de2d3f5958f27479de59',
  ),
};

/// The package whose `lib/models.dart` pins each task's model.
String packageOf(String task) => switch (task) {
  'audio_classifier' => 'mediapipe-task-audio',
  'language_detector' ||
  'text_classifier' ||
  'text_embedder' ||
  'embedding_gemma' ||
  'text_proofreader' ||
  'text_summarizer' => 'mediapipe-task-text',
  _ => 'mediapipe-task-vision',
};

/// The text package's generative tasks and EmbeddingGemma, 419 MB of models
/// in all, so a target bundles them only when `--tasks` asks for them: the
/// emulator test build does, the published galleries do not. Their suite
/// compares with Google's references, bundled from `--modern-text-reference`
/// or the package's checked-in macOS fixtures.
const modernTextTasks = {
  'embedding_gemma',
  'text_proofreader',
  'text_summarizer',
};

/// The checked-in fixture each modern text task's reference comes from.
const modernTextReferences = {
  'embedding_gemma': 'embedding_gemma',
  'text_proofreader': 'proofreader',
  'text_summarizer': 'summarizer',
};

/// Tasks outside the vision package, which its build hook must not be asked
/// for.
const nonVisionTasks = {
  'audio_classifier',
  'language_detector',
  'text_classifier',
  'text_embedder',
  ...modernTextTasks,
};

/// Every task Google's Android SDKs serve.
const androidTasks = {
  'audio_classifier',
  'embedding_gemma',
  'face_detector',
  'face_landmarker',
  'gesture_recognizer',
  'hand_landmarker',
  'holistic_landmarker',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'language_detector',
  'object_detector',
  'pose_landmarker',
  'text_classifier',
  'text_embedder',
  'text_proofreader',
  'text_summarizer',
};

/// Vision tasks Google's macOS engine serves, as `macosEngineTasks` in the
/// vision package's `sdk_downloads.dart` lists them. Core bundles the engine
/// (about 95 MB) only for an app that sets `tasks_runtime: true`.
const macosEngineTasks = {
  'face_landmarker',
  'gesture_recognizer',
  'hand_landmarker',
  'holistic_landmarker',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'object_detector',
  'pose_landmarker',
};

/// Every task a macOS gallery can bundle: the engine's, Face Detector from its
/// published source build, and text and audio, which the engine also serves.
const macosTasks = {...macosEngineTasks, 'face_detector', ...nonVisionTasks};

/// The tasks each target this tool prepares can bundle.
const targetTasks = <String, Set<String>>{
  'android/arm64': androidTasks,
  'android/x64': androidTasks,
  'macos/arm64': macosTasks,
};

/// Whether a macOS gallery bundling [tasks] needs Google's engine: anything
/// but the face pair does, and Face Landmarker then runs on it too.
bool needsMacosEngine(Iterable<String> tasks) => tasks.any(
  (task) =>
      task != 'face_landmarker' &&
      (macosEngineTasks.contains(task) || nonVisionTasks.contains(task)),
);

/// Sample inputs, from the test fixtures and the gallery's own samples, by
/// the name the gallery reads them under.
const samples = <String, String>{
  'packages/mediapipe-task-vision/test/fixtures/face_detection/landmark-ex1.jpg':
      'portrait.jpg',
  'packages/mediapipe-task-vision/test/fixtures/face_detection/group-shot-bounding-box-ex1.jpeg':
      'group.jpeg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/right_hands.jpg':
      'hands.jpg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/pose.jpg':
      'pose.jpg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/thumb_up.jpg':
      'thumb_up.jpg',
  'packages/mediapipe-task-vision/test/fixtures/interactive_segmentation/cats_and_dogs.jpg':
      'animals.jpg',
  'packages/mediapipe-task-audio/test/fixtures/speech_16000_hz_mono.wav':
      'speech_16000_hz_mono.wav',
  'packages/mediapipe-task-audio/test/fixtures/speech_48000_hz_mono.wav':
      'speech_48000_hz_mono.wav',
  'packages/mediapipe-task-audio/test/fixtures/two_heads_16000_hz_mono.wav':
      'two_heads_16000_hz_mono.wav',
  'gallery/samples/dog.jpg': 'dog.jpg',
  'gallery/samples/cat.png': 'cat.png',
  'gallery/samples/elephant.png': 'elephant.png',
  // The video file mode's clip and the clip that checks a file's rotation,
  // made from the fixtures above by gallery/tool/make_sample_clip.py.
  'gallery/samples/scene.mp4': 'scene.mp4',
  'gallery/samples/rotated.mp4': 'rotated.mp4',
};

/// The photos Google's Image Embedding demo compares, bundled only with it.
const embedderSamples = {'dog.jpg', 'cat.png', 'elephant.png'};
