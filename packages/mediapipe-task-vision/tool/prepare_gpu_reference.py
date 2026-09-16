"""Generate independent GPU references on the machine that runs the Dart tests.

Does not change checked-in goldens, models, task code or test tolerances.
The default creates an isolated Python environment from a checksum-pinned wheel.
--python reuses an existing environment; the generators still verify its native
library, runtime version, model digests and input fixture bytes.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
LIBRARY_SHA256 = "aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f"
WHEEL_URL = (
    "https://files.pythonhosted.org/packages/42/d7/"
    "3a5dfaa86128db110c62a4d0f0c948304817932c9dd3257313bbdf24f7d5/"
    "mediapipe-1.0.0-py3-none-macosx_11_0_arm64.whl"
)
WHEEL_SHA256 = "7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82"
FACE_TASKS = (("face_detector", "face_detection"),
              ("face_landmarker", "face_landmarker"))
FACE_FILES = (
    "face_detection/official_gpu_reference.json",
    "face_detection/official_gpu_video_reference.json",
    "face_landmarker/official_gpu_reference.json",
)
# Every suite reading a GPU reference under MEDIAPIPE_GPU_REFERENCE_DIR needs
# its references generated here; a missing one fails the suite at load time.
OBJECT_TASKS = (("object_detector", "object_detection"),)
OBJECT_FILES = (
    "object_detection/official_gpu_reference.json",
    "object_detection/official_gpu_video_reference.json",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def difference(reference, current):
    """Record host differences in the official API, never adjust expectations."""
    groups = {}
    structural = []

    def visit(old, new, path):
        if isinstance(old, dict) and isinstance(new, dict):
            if old.keys() != new.keys():
                structural.append(path + ": object keys differ")
            for key in old.keys() & new.keys():
                visit(old[key], new[key], path + "." + key)
        elif isinstance(old, list) and isinstance(new, list):
            if len(old) != len(new):
                structural.append(path + ": list length differs")
            for i, (left, right) in enumerate(zip(old, new)):
                visit(left, right, f"{path}[{i}]")
        elif isinstance(old, (int, float)) and not isinstance(old, bool):
            if not isinstance(new, (int, float)):
                structural.append(path + ": numeric type differs")
                return
            group = next((name for name in (
                "face_landmarks", "face_blendshapes",
                "facial_transformation_matrixes", "bounding_box",
                "keypoints", "categories",
            ) if "." + name in path), "other")
            error = abs(old - new)
            item = groups.setdefault(group, {"maximum_absolute_error": 0.0,
                                             "values": 0, "path": None})
            item["values"] += 1
            if error > item["maximum_absolute_error"]:
                item.update(maximum_absolute_error=error, path=path,
                            checked_in=old, same_host=new)
        elif old != new:
            structural.append(path + ": value differs")

    visit(reference["cases"], current["cases"], "cases")
    return {"numeric_groups": groups, "structural_differences": structural}


def face_test_root(destination):
    """Builds a face-only root package for the Dart suites.

    This package's own pubspec selects tasks whose macOS runtime exists only in
    a maintainer source build, so `dart test` run here cannot resolve its assets
    on a machine without one. Only the root package's user_defines reach a build
    hook, so an isolated root scoped to the two published face runtimes keeps
    this job on the public download path it exists to check.
    """
    if destination.exists():
        shutil.rmtree(destination)
    (destination / "test").mkdir(parents=True)
    for folder in ("support", "fixtures/face_detection", "fixtures/face_landmarker"):
        shutil.copytree(PACKAGE / "test" / folder, destination / "test" / folder)
    for name in ("face_detector_test.dart", "face_landmarker_test.dart"):
        shutil.copyfile(PACKAGE / "test" / name, destination / "test" / name)
    (destination / "models").mkdir()
    for name in ("blaze_face_short_range.tflite", "face_landmarker.task"):
        shutil.copyfile(PACKAGE / "models" / name, destination / "models" / name)
    (destination / "pubspec.yaml").write_text(f"""name: mediapipe_gpu_face_tests
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  mediapipe_flutter_vision:
    path: {PACKAGE}
dev_dependencies:
  crypto: ^3.0.6
  test: ^1.31.0
hooks:
  user_defines:
    mediapipe_flutter_vision:
      tasks: [face_detector, face_landmarker]
""")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", type=Path, help="Existing MediaPipe 1.0.0 Python")
    parser.add_argument("--output-dir", type=Path, default=REPO / "build/gpu-reference")
    parser.add_argument("--test", action="store_true",
                        help="Also run both Dart face suites with these references")
    # Opt-in because the public-runtime comparison job downloads face models only.
    parser.add_argument("--object-detector", action="store_true",
                        help="Also generate Object Detector references, for a "
                             "checkout whose object detection model is present")
    args = parser.parse_args()
    tasks = FACE_TASKS + (OBJECT_TASKS if args.object_detector else ())
    files = FACE_FILES + (OBJECT_FILES if args.object_detector else ())
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("GPU references require macOS arm64.")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Do not leave a stale receipt if generation or model verification fails.
    provenance = output / "provenance.json"
    if provenance.exists():
        provenance.unlink()
    python = args.python
    if python is None:
        environment = REPO / "build/codex-tmp/gpu-reference-env"
        if not (environment / "bin/python").exists():
            subprocess.run([sys.executable, "-m", "venv", str(environment)], check=True)
        python = environment / "bin/python"
        subprocess.run([
            str(python), "-m", "pip", "install", "--disable-pip-version-check",
            WHEEL_URL + "#sha256=" + WHEEL_SHA256,
        ], check=True)
    python = python.absolute()
    env = {**os.environ, "MPLCONFIGDIR": str(output / "matplotlib")}
    summaries = {}
    graphics = {}
    for task, folder in tasks:
        log_file = output / (task + ".log")
        command = [str(python), "-B", str(PACKAGE / "tool" /
                   f"generate_{task}_reference.py"), "--delegate", "gpu",
                   "--output-dir", str(output / folder)]
        with log_file.open("w") as log:
            result = subprocess.run(command, env=env, stdout=log,
                                    stderr=subprocess.STDOUT)
        log = log_file.read_text()
        print("\n".join(log.splitlines()[-12:]), flush=True)
        result.check_returncode()
        if "Created TensorFlow Lite delegate for Metal." not in log:
            raise RuntimeError(f"Official {task} did not confirm Metal creation")
        graphics[task] = sorted(set(re.findall(r"GL version:.*", log)))
    for name in files:
        baseline = json.loads((PACKAGE / "test/fixtures" / name).read_text())
        reference = json.loads((output / name).read_text())
        summaries[name] = difference(baseline, reference)
    report = {
        "source": "official-python-api", "runtime": "mediapipe==1.0.0",
        "library_sha256": LIBRARY_SHA256,
        "wheel_url": WHEEL_URL, "wheel_sha256": WHEEL_SHA256,
        "delegate": "GPU", "metal_confirmed": True,
        "os": platform.platform(), "machine": platform.machine(),
        "graphics": graphics, "files": {name: digest(output / name) for name in files},
        "checked_in_reference_differences": summaries,
        "scope": "Official wheel on this host versus checked-in physical-Mac "
                 "GPU references. Dart tests separately compare the native task "
                 "with these independently generated outputs.",
    }
    provenance.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summaries, indent=2), flush=True)
    print(f"Verified official GPU references: {output}", flush=True)
    if args.test:
        env["MEDIAPIPE_GPU_REFERENCE_DIR"] = str(output)
        root = face_test_root(REPO / "build/gpu-face-tests")
        with (output / "dart-tests.log").open("w") as log:
            result = subprocess.run(["dart", "pub", "get"], cwd=root, env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
            if result.returncode == 0:
                result = subprocess.run([
                    "dart", "test", "test/face_detector_test.dart",
                    "test/face_landmarker_test.dart", "--reporter", "expanded",
                ], cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        print("\n".join((output / "dart-tests.log").read_text().splitlines()[-30:]),
              flush=True)
        result.check_returncode()


if __name__ == "__main__":
    main()
