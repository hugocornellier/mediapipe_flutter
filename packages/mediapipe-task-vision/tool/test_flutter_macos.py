"""Generate an isolated Flutter host and test macOS release-mode native bundling."""
from pathlib import Path
import shutil
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
APP = PACKAGE.parents[1] / "build/flutter_vision_smoke"


def run(args):
    subprocess.run(args, cwd=APP, check=True)


def main():
    if not (APP / ".metadata").exists():
        subprocess.run([
            "flutter", "create", "--platforms=macos", "--empty", "--no-pub",
            "--project-name", "mediapipe_vision_smoke", str(APP),
        ], check=True)
    (APP / "pubspec.yaml").write_text("""name: mediapipe_vision_smoke
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../../packages/mediapipe-task-vision
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
flutter:
  assets:
    - assets/model.tflite
    - assets/portrait.rgb
""")
    (APP / "assets").mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / "models/blaze_face_short_range.tflite",
                    APP / "assets/model.tflite")
    shutil.copyfile(PACKAGE / "test/fixtures/face_detection/portrait-301x209.rgb",
                    APP / "assets/portrait.rgb")
    (APP / "integration_test").mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / "tool/flutter_smoke_test.dart.template",
                    APP / "integration_test/face_detector_test.dart")
    shutil.copyfile(PACKAGE / "tool/flutter_release_smoke.dart.template",
                    APP / "lib/main.dart")
    # Flutter defaults release builds to a universal binary. This runtime is arm64.
    config = APP / "macos/Runner/Configs/AppInfo.xcconfig"
    settings = config.read_text()
    if "EXCLUDED_ARCHS = x86_64" not in settings:
        config.write_text(settings + "\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n")
    run(["flutter", "pub", "get"])
    run(["flutter", "test", "-d", "macos",
         "integration_test/face_detector_test.dart", "--reporter", "expanded"])
    run(["flutter", "build", "macos", "--release"])
    executable = APP / ("build/macos/Build/Products/Release/"
                        "mediapipe_vision_smoke.app/Contents/MacOS/mediapipe_vision_smoke")
    subprocess.run([str(executable)], cwd=APP, check=True, timeout=60)


if __name__ == "__main__":
    main()
