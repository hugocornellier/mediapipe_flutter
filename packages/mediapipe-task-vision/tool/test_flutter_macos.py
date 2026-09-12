"""Generate an isolated Flutter host and test macOS release-mode native bundling."""
from pathlib import Path
import json
import os
import shutil
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
APP = PACKAGE.parents[1] / "build/flutter_vision_smoke"


def test_app(app=APP, package=PACKAGE, env=None):
    def run(args):
        subprocess.run(args, cwd=app, env=env, check=True)

    if not (app / ".metadata").exists():
        subprocess.run([
            "flutter", "create", "--platforms=macos", "--empty", "--no-pub",
            "--project-name", "mediapipe_vision_smoke", str(app),
        ], env=env, check=True)
    dependency = json.dumps(os.path.relpath(package, app))
    (app / "pubspec.yaml").write_text(f"""name: mediapipe_vision_smoke
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: {dependency}
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
flutter:
  assets:
    - assets/model.tflite
    - assets/face_landmarker.task
    - assets/portrait.rgb
""")
    (app / "assets").mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / "models/blaze_face_short_range.tflite",
                    app / "assets/model.tflite")
    shutil.copyfile(PACKAGE / "models/face_landmarker.task",
                    app / "assets/face_landmarker.task")
    shutil.copyfile(PACKAGE / "test/fixtures/face_detection/portrait-301x209.rgb",
                    app / "assets/portrait.rgb")
    (app / "integration_test").mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / "tool/flutter_smoke_test.dart.template",
                    app / "integration_test/face_detector_test.dart")
    shutil.copyfile(PACKAGE / "tool/flutter_release_smoke.dart.template",
                    app / "lib/main.dart")
    # Flutter defaults release builds to a universal binary. This runtime is arm64.
    config = app / "macos/Runner/Configs/AppInfo.xcconfig"
    settings = config.read_text()
    if "EXCLUDED_ARCHS = x86_64" not in settings:
        config.write_text(settings + "\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n")
    run(["flutter", "pub", "get"])
    run(["flutter", "test", "-d", "macos",
         "integration_test/face_detector_test.dart", "--reporter", "expanded"])
    run(["flutter", "build", "macos", "--release"])
    executable = app / ("build/macos/Build/Products/Release/"
                        "mediapipe_vision_smoke.app/Contents/MacOS/mediapipe_vision_smoke")
    subprocess.run([str(executable)], cwd=app, env=env, check=True, timeout=60)


if __name__ == "__main__":
    test_app()
