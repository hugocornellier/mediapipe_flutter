"""Download the browser tasks' models using the vision package's pinned metadata."""
import hashlib
from pathlib import Path
import re
import urllib.request

vision = Path(__file__).resolve().parents[2] / 'mediapipe-task-vision'
source = (vision / 'lib/models.dart').read_text()
# Dart constant prefix -> file name, for every task the browser adapter serves.
MODELS = {'faceLandmarker': 'face_landmarker.task',
          'handLandmarker': 'hand_landmarker.task',
          'poseLandmarkerLite': 'pose_landmarker_lite.task',
          'gestureRecognizer': 'gesture_recognizer.task',
          'holisticLandmarker': 'holistic_landmarker.task',
          'blazeFaceShortRange': 'blaze_face_short_range.tflite',
          'efficientDetLite0': 'efficientdet_lite0.tflite',
          'efficientNetLite0': 'efficientnet_lite0.tflite',
          'mobileNetV3Small': 'mobilenet_v3_small.tflite',
          'deepLabV3': 'deeplab_v3.tflite',
          'magicTouch': 'magic_touch.tflite',
          'interactiveSegmenterModel': 'interactive_segmentation.task'}
for constant, name in MODELS.items():
    block = re.search(constant + r"Url\s*=\s*((?:'[^']*'\s*)+);", source).group(1)
    url = ''.join(re.findall(r"'([^']*)'", block))
    expected = re.search(constant + r"Sha256\s*=\s*'([0-9a-f]{64})';", source).group(1)
    destination = vision / 'models' / name
    if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != expected:
        data = urllib.request.urlopen(url, timeout=120).read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f'Official {name} checksum mismatch')
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print(f'Verified official {name}: {expected}')
