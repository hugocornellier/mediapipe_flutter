#!/usr/bin/env bash
# Checks Face Detector and Face Landmarker on a Linux x64 machine with a real
# GPU. CI can only use Mesa's software renderer, renamed past Google's check;
# this runs Google's unmodified GPU path on actual hardware, compares the Dart
# tasks with Google's own 1.0.1 GPU output on this machine, and times CPU
# against GPU. Run from anywhere in the repository:
#
#   bash packages/mediapipe-task-vision/tool/test_linux_gpu.sh
#
# Needs: dart (Flutter 3.44.8 or Dart 3.12), python3 with venv, and the
# system EGL and OpenGL ES libraries (Debian/Ubuntu: libegl1 libgles2) with
# your GPU vendor's driver. Writes build/linux-gpu-check/; send that folder
# back.
set -euo pipefail

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
PACKAGE=$REPO/packages/mediapipe-task-vision
OUT=$REPO/build/linux-gpu-check
REFERENCES=$OUT/gpu-reference
rm -rf "$OUT"
mkdir -p "$OUT"
exec > >(tee "$OUT/run.log") 2>&1

[ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] || { echo "Needs Linux x86_64."; exit 1; }
for library in libEGL.so.1 libGLESv2.so.2; do
  ldconfig -p | grep -q "$library" || {
    echo "Missing $library. Install it, for example: sudo apt-get install libegl1 libgles2"
    exit 1
  }
done
# A physical GPU passes Google's check unrenamed; a leftover CI setting must not.
unset force_gl_renderer

{
  echo "commit: $(git -C "$REPO" rev-parse HEAD)"
  echo "kernel: $(uname -r)"
  grep -m1 PRETTY_NAME /etc/os-release || true
  echo "dart: $(dart --version 2>&1)"
  echo "python: $(python3 --version)"
  echo "EGL_PLATFORM: ${EGL_PLATFORM:-default}"
  command -v nvidia-smi > /dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
  command -v lspci > /dev/null && lspci | grep -iE 'vga|3d|display'
} | tee "$OUT/machine.txt"

echo "== Face models"
(cd "$PACKAGE" && dart pub get > /dev/null && dart tool/download_model.dart && dart tool/download_face_landmarker.dart)

echo "== Google's 1.0.1 GPU references, then the Dart GPU suites against them"
python3 -B "$PACKAGE/tool/prepare_gpu_reference.py" --output-dir "$REFERENCES" --test

echo "== CPU and GPU timing with Google's Python API (Face Landmarker, 60 images)"
"$REPO/build/codex-tmp/gpu-reference-env/bin/python" -B - "$PACKAGE" <<'EOF' | tee "$OUT/timing.json"
import json, statistics, sys, time
from pathlib import Path
import mediapipe as mp
from mediapipe.tasks.python import vision

package = Path(sys.argv[1])
image = mp.Image.create_from_file(str(package / "test/fixtures/face_detection/landmark-ex1.jpg"))
results = {"mediapipe": mp.__version__}
for name in ("CPU", "GPU"):
    started = time.perf_counter()
    options = vision.FaceLandmarkerOptions(base_options=mp.tasks.BaseOptions(
        model_asset_path=str(package / "models/face_landmarker.task"),
        delegate=getattr(mp.tasks.BaseOptions.Delegate, name)))
    with vision.FaceLandmarker.create_from_options(options) as task:
        created = time.perf_counter()
        task.detect(image)
        first = time.perf_counter()
        times = []
        for _ in range(60):
            start = time.perf_counter()
            task.detect(image)
            times.append((time.perf_counter() - start) * 1000)
    results[name] = {"create_ms": round((created - started) * 1000, 1),
                     "first_ms": round((first - created) * 1000, 1),
                     "median_ms": round(statistics.median(times), 2)}
print(json.dumps(results, indent=2))
EOF

grep -h "GL version:" "$REFERENCES"/*.log | sort -u | tee "$OUT/renderer.txt"
cp "$REFERENCES/provenance.json" "$OUT/"
echo "PASSED. Send back $OUT (run.log, machine.txt, renderer.txt, timing.json, provenance.json)."
