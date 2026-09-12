"""Build a pinned, official CPU face task for macOS arm64.

Requires Xcode, Bazelisk, CMake and Ninja. No MediaPipe source is patched.
Run from any directory. Output is bundled by hook/build.dart.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
REVISION = "6d31f1ebc3284db74d211d62bdc4f0a0c29ea120"
SOURCE = "https://github.com/google-ai-edge/mediapipe.git"
TARGET = "//mediapipe/tasks/c/vision/face_detector:libface_detector.dylib"
OPENCV_REVISION = "49486f61fb25722cbcf586b7f4320921d46fb38e"
FLAGS = [
    "--config=darwin_arm64", "-c", "opt", "--strip=always",
    "--define=MEDIAPIPE_DISABLE_GPU=1",
    "--repo_env=HERMETIC_PYTHON_VERSION=3.12", "--jobs=8",
    "--linkopt=-Wl,-headerpad_max_install_names",
    "--linkopt=-Wl,-u,_MpFaceDetectorCreate",
    "--linkopt=-Wl,-u,_MpImageCreateFromFile",
    "--linkopt=-Wl,-exported_symbol,_Mp*",
]
SYMBOLS = [
    "MpFaceDetectorCreate", "MpFaceDetectorDetectImage",
    "MpFaceDetectorCloseResult", "MpFaceDetectorClose",
    "MpImageCreateFromFile", "MpImageCreateFromUint8Data",
    "MpImageGetWidth", "MpImageGetHeight", "MpImageFree", "MpErrorFree",
]


def run(arguments, cwd=None):
    print(shlex.join(map(str, arguments)), flush=True)
    subprocess.run(arguments, cwd=cwd, check=True)


def capture(arguments, cwd=None):
    return subprocess.check_output(arguments, cwd=cwd, text=True).strip()


def build_opencv(root):
    source = root / "opencv"
    build = root / "opencv-build"
    install = root / "opencv-install"
    if not source.exists():
        root.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", "--branch", "4.12.0",
             "https://github.com/opencv/opencv.git", str(source)])
    if capture(["git", "rev-parse", "HEAD"], source) != OPENCV_REVISION:
        raise SystemExit("Refusing unpinned OpenCV checkout.")
    if capture(["git", "diff", "--name-only", "HEAD"], source):
        raise SystemExit("Refusing modified OpenCV source.")
    configuration = [
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={install}",
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0", "-DCMAKE_OSX_ARCHITECTURES=arm64",
        "-DBUILD_LIST=core,imgproc", "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_TESTS=OFF", "-DBUILD_PERF_TESTS=OFF", "-DBUILD_EXAMPLES=OFF",
        "-DBUILD_opencv_apps=OFF", "-DBUILD_JAVA=OFF",
        "-DBUILD_opencv_python2=OFF", "-DBUILD_opencv_python3=OFF",
        "-DBUILD_ZLIB=ON",
    ] + [f"-DWITH_{feature}=OFF" for feature in (
        "OPENCL", "IPP", "ITT", "LAPACK", "EIGEN", "OPENMP", "TBB", "JPEG",
        "PNG", "TIFF", "WEBP", "OPENEXR", "JASPER", "OPENJPEG", "AVIF",
        "FFMPEG", "AVFOUNDATION", "GSTREAMER", "VTK",
    )]
    run(["cmake", "-S", str(source), "-B", str(build), "-G", "Ninja",
         *configuration])
    run(["cmake", "--build", str(build), "--parallel", "8"])
    run(["cmake", "--install", str(build)])
    (install / "WORKSPACE").write_text('workspace(name = "macos_opencv")\n')
    (install / "BUILD.bazel").write_text('''load("@rules_cc//cc:cc_library.bzl", "cc_library")
cc_library(
    name = "opencv",
    srcs = ["lib/libopencv_imgproc.a", "lib/libopencv_core.a"] +
           glob(["lib/opencv4/3rdparty/*.a"]),
    hdrs = glob(["include/opencv4/**/*.h*"]),
    includes = ["include/opencv4"],
    visibility = ["//visibility:public"],
)
''')
    return install, configuration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", choices=("face_detector", "face_landmarker"),
                        default="face_detector")
    parser.add_argument("--source-dir", type=Path,
                        default=REPO / "build/native/mediapipe-v1.0.0")
    parser.add_argument("--bazel-cache", type=Path,
                        default=REPO / "build/native/bazel")
    parser.add_argument("--opencv-root", type=Path,
                        default=REPO / "build/native")
    args = parser.parse_args()
    task = args.task
    landmarker = task == "face_landmarker"
    target = f"//mediapipe/tasks/c/vision/{task}:lib{task}.dylib"
    flags = [flag.replace("MpFaceDetector", "MpFaceLandmarker")
             if landmarker else flag for flag in FLAGS]
    symbols = [name.replace("MpFaceDetector", "MpFaceLandmarker")
               if landmarker else name for name in SYMBOLS]
    symbols.append("MpFaceLandmarkerDetectForVideo" if landmarker
                   else "MpFaceDetectorDetectForVideo")
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("This build supports macOS arm64 only.")
    source = args.source_dir.resolve()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", "--branch", "v1.0.0", SOURCE, str(source)])
    revision = capture(["git", "rev-parse", "HEAD"], source)
    if revision != REVISION:
        raise SystemExit(f"Refusing unpinned checkout: {revision}")
    if capture(["git", "diff", "--name-only", "HEAD"], source):
        raise SystemExit("Refusing a checkout with modified tracked source files.")
    opencv, opencv_configuration = build_opencv(args.opencv_root.resolve())
    run(["bazelisk", f"--output_user_root={args.bazel_cache.resolve()}",
         "build", *flags, f"--override_repository=macos_opencv={opencv}", target], source)
    built = source / f"bazel-bin/mediapipe/tasks/c/vision/{task}/lib{task}.dylib"
    library = ctypes.CDLL(str(built))
    for name in symbols:
        getattr(library, name)  # Reject the upstream target's empty C API build.
    dependencies = capture(["otool", "-L", str(built)]).splitlines()[2:]
    for dependency in dependencies:
        name = dependency.strip().split(" (", 1)[0]
        if not name.startswith(("/System/Library/", "/usr/lib/")):
            raise SystemExit(f"Non-system dynamic dependency: {name}")

    output = PACKAGE / "build/native"
    if landmarker:
        output = output / task
    output.mkdir(parents=True, exist_ok=True)
    smoke = output / "native_smoke"
    run(["xcrun", "clang++", "-std=c++17", "-I", str(source),
         str(PACKAGE / ("tool/native_landmarker_smoke.cc" if landmarker
                        else "tool/native_smoke.cc")), str(built), "-o", str(smoke)])
    # The upstream library's install name is bare; this isolated native test
    # points dyld at it. Flutter/Dart rewrite the ID when bundling.
    subprocess.run(
        [str(smoke), str(PACKAGE / ("models/face_landmarker.task" if landmarker
                                   else "models/blaze_face_short_range.tflite")),
         str(PACKAGE / "test/fixtures/face_detection/landmark-ex1.jpg")],
        env={**os.environ, "DYLD_LIBRARY_PATH": str(built.parent)}, check=True,
    )
    destination = output / f"lib{task}.dylib"
    temporary = output / f"lib{task}.dylib.tmp"
    shutil.copyfile(built, temporary)
    temporary.replace(destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    manifest = dict(
        source=SOURCE, revision=REVISION, version="1.0.0",
        target=target, flags=flags, platform="macos", architecture="arm64",
        opencv_revision=OPENCV_REVISION, opencv_configuration=opencv_configuration,
        sha256=digest, bytes=destination.stat().st_size,
        bazel_version=(source / ".bazelversion").read_text().strip(),
        xcode=capture(["xcodebuild", "-version"]),
        clang=capture(["xcrun", "clang", "--version"]),
    )
    manifest_path = output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    # Prepare a reviewable release artifact; this tool never uploads anything.
    archive = output / f"mediapipe-{task.replace('_', '-')}-1.0.0-macos-arm64.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        bundle.add(destination, arcname=destination.name)
        bundle.add(manifest_path, arcname=manifest_path.name)
        for name in ("LICENSE", "NOTICE"):
            path = PACKAGE / "third_party" / name
            bundle.add(path, arcname=name)
        bundle.add(opencv / "share/licenses/opencv4", arcname="opencv-licenses")
        bundle.add(args.opencv_root.resolve() / "opencv/LICENSE",
                   arcname="opencv-licenses/LICENSE")
        bundle.add(PACKAGE / "third_party/OPENCV_CAROTENE_NOTICES",
                   arcname="opencv-licenses/CAROTENE_NOTICES")
    print(f"Verified {destination.stat().st_size:,} byte library: {digest}")
    print(f"Release candidate: {archive}")


if __name__ == "__main__":
    main()
