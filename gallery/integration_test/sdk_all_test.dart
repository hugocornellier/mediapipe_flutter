import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sdk_face_landmarker_test.dart' as face;
import 'runtime_test.dart' as runtime;
import 'sdk_detection_tasks_test.dart' as detection;
import 'sdk_embedder_test.dart' as embedder;
import 'sdk_hand_landmarker_test.dart' as hand;
import 'sdk_interactive_segmenter_test.dart' as interactive;
import 'sdk_landmark_tasks_test.dart' as landmarks;
import 'sdk_segmenter_test.dart' as segmenter;
import 'sdk_text_audio_test.dart' as text_audio;

// Every official SDK suite in one app launch: on Firebase Test Lab, where each
// device run counts against a small daily quota, and on the CI emulator, where
// each extra install and launch risked losing the emulator. Build with
// SDK_GPU=required on a physical device so a GPU refusal fails its test instead
// of being recorded.
// The live tiles run last: they open the camera, which is dark in a device rack.
void main() {
  // The binding reports the run as finished to Android from a tearDownAll it
  // registers when first created. Created inside a suite's group, it would end
  // the instrumentation after that group; created here, after every group.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('face landmarker', face.main);
  group('hand', hand.main);
  group('landmark tasks', landmarks.main);
  group('detection and classification', detection.main);
  group('embedder', embedder.main);
  group('segmenter', segmenter.main);
  group('interactive segmenter', interactive.main);
  group('text and audio', text_audio.main);
  group('live tiles', runtime.main);
}
