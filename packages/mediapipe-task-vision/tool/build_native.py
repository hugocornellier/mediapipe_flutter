"""Build the pinned, official CPU/Metal MediaPipe task runtime for macOS arm64.

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
import re
import shlex
import shutil
import subprocess
import tarfile

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
REVISION = "6d31f1ebc3284db74d211d62bdc4f0a0c29ea120"
SOURCE = "https://github.com/google-ai-edge/mediapipe.git"
# Google's own wheel target: one library exporting every task the open-source
# C API offers. Linking each task separately would repeat the shared graph
# runtime, about 12 MB, in every dylib and would need a namespace per task.
# MagicTouch, the modern stateful interactive segmenter, is not open source;
# it stays on core's official 1.0.1 runtime and only its legacy predecessor
# builds here.
TARGET = "//mediapipe/tasks/c:libmediapipe"
LIBRARY = "libmediapipe.dylib"
OPENCV_REVISION = "49486f61fb25722cbcf586b7f4320921d46fb38e"
FLAGS = [
    "--config=darwin_arm64", "-c", "opt", "--strip=always",
    "--repo_env=HERMETIC_PYTHON_VERSION=3.12", "--jobs=8",
    "--linkopt=-Wl,-headerpad_max_install_names",
    "--linkopt=-Wl,-exported_symbol,_Mp*",
    # Apple Silicon has streaming SVE through SME, but no non-streaming SVE.
    # Clang can otherwise auto-vectorize KleidiAI's SME C wrappers before
    # their assembly kernels enter streaming mode, causing SIGILL on M4.
    # Keep explicit architecture kernels; disable automatic vectorization
    # only in the C wrappers. Upstream MediaPipe/KleidiAI sources stay intact.
    "--per_file_copt=external/KleidiAI/.*[.]c@-fno-vectorize,-fno-slp-vectorize",
]
# The C entry points live in static archives the linker would otherwise drop,
# because nothing inside the shared object references them.
FORCED = "MpImageCreateFromFile"
# Retained for tool/build_ios_simulator.py, which still links one dylib per
# task because no combined runtime is published for the simulator.
SYMBOLS = [
    "MpFaceDetectorCreate", "MpFaceDetectorDetectImage",
    "MpFaceDetectorCloseResult", "MpFaceDetectorClose",
    "MpImageCreateFromFile", "MpImageCreateFromUint8Data",
    "MpImageGetWidth", "MpImageGetHeight", "MpImageFree", "MpErrorFree",
]
# Objective-C names are process-global even when the linker hides C symbols.
# One library removes the task-versus-task collision, but an app that also
# loads LiteRT or MediaPipe directly still brings its own copies of these
# classes. Rename identifiers at compilation; sources and graphs stay intact.
OBJC_IDENTIFIERS = (
    "TFLBufferConvert", "MPPMetalUtil", "MPPMetalHelper", "MPPGraph",
    "MPPTimestampConverter", "GUSUtilStatusWrapper", "MPPMetalSharedResources",
    "MPPGraphDelegate", "GUSGoogleUtilStatus", "gus_errorWithStatus", "gus_status",
)
OBJC_PREFIX = "MpfTasks"
# Each smoke exercises a different graph shape against the same library.
SMOKES = (
    ("face_detector", "tool/native_smoke.cc",
     "models/blaze_face_short_range.tflite"),
    ("face_landmarker", "tool/native_landmarker_smoke.cc",
     "models/face_landmarker.task"),
)


def run(arguments, cwd=None):
    print(shlex.join(map(str, arguments)), flush=True)
    subprocess.run(arguments, cwd=cwd, check=True)


def capture(arguments, cwd=None):
    return subprocess.check_output(arguments, cwd=cwd, text=True).strip()


def linked_packages(source):
    """Packages the combined target links, read from its own BUILD file.

    Reading the dependency list keeps this tool honest when upstream adds or
    removes a task, instead of pinning a list that silently goes stale.
    """
    build = (source / "mediapipe/tasks/c/BUILD").read_text()
    deps = re.search(r'name = "mediapipe_source".*?deps = \[(.*?)\]',
                     build, re.DOTALL)
    if deps is None:
        raise SystemExit(f"Could not read the dependencies of {TARGET}.")
    packages = sorted(set(re.findall(r'"//([^":]+):', deps.group(1))))
    if not packages:
        raise SystemExit(f"{TARGET} declares no package dependencies.")
    return packages


def exported_functions(source, packages):
    """Every MP_EXPORT function the linked packages declare."""
    names = set()
    for package in packages:
        for header in sorted((source / package).glob("*.h")):
            text = re.sub(r"^\s*#\s*define\s+MP_EXPORT.*$", "",
                          header.read_text(errors="ignore"), flags=re.MULTILINE)
            for declaration in re.findall(r"MP_EXPORT\s+([^;{]*?)\(",
                                          text, re.DOTALL):
                identifiers = re.findall(r"\b([A-Za-z_]\w*)\b", declaration)
                if identifiers and identifiers[-1].startswith("Mp"):
                    names.add(identifiers[-1])
    if not names:
        raise SystemExit("Found no MP_EXPORT declarations; check the checkout.")
    return names


def verify_objc_namespace(library):
    metadata = capture(["otool", "-ov", str(library)])
    section = re.search(
        r"Contents of [^\n]*__objc_classlist[^\n]*\n(.*?)(?=\nContents of |\Z)",
        metadata, re.DOTALL)
    classes = set(re.findall(
        r"^[0-9a-f]+ 0x[0-9a-f]+ _OBJC_CLASS_\$_(\w+)$",
        section.group(1) if section else "", re.MULTILINE))
    expected = {f"{OBJC_PREFIX}_{name}" for name in OBJC_IDENTIFIERS[:7]}
    if classes != expected:
        raise SystemExit(f"Unexpected Objective-C classes: {classes}; expected {expected}")
    # NSError categories also share selectors process-wide.
    for selector in ("gus_status", "gus_errorWithStatus"):
        if re.search(rf"\s{selector}:?$", metadata, re.MULTILINE):
            raise SystemExit(f"Unnamespaced NSError selector: {selector}")
    print(f"Verified {len(classes)} isolated Objective-C classes.")


def build_opencv(root, *, ios_simulator=False):
    source = root / "opencv"
    suffix = "-ios-simulator" if ios_simulator else ""
    build = root / f"opencv{suffix}-build"
    install = root / f"opencv{suffix}-install"
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
        f"-DCMAKE_OSX_DEPLOYMENT_TARGET={'13.0' if ios_simulator else '11.0'}",
        "-DCMAKE_OSX_ARCHITECTURES=arm64",
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
    if ios_simulator:
        configuration.extend([
            "-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphonesimulator",
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
            "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO",
        ])
    run(["cmake", "-S", str(source), "-B", str(build), "-G", "Ninja",
         *configuration])
    run(["cmake", "--build", str(build), "--parallel", "8"])
    run(["cmake", "--install", str(build)])
    repository = "ios_opencv" if ios_simulator else "macos_opencv"
    (install / "WORKSPACE").write_text(f'workspace(name = "{repository}")\n')
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
    parser.add_argument("--cpu-only", action="store_true",
                        help="Omit Metal support for a CPU-only maintainer build")
    parser.add_argument("--output-dir", type=Path,
                        help="Override the output directory for an isolated candidate")
    parser.add_argument("--source-dir", type=Path,
                        default=REPO / "build/native/mediapipe-v1.0.0")
    parser.add_argument("--bazel-cache", type=Path,
                        default=REPO / "build/native/bazel")
    parser.add_argument("--opencv-root", type=Path,
                        default=REPO / "build/native")
    args = parser.parse_args()
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

    packages = linked_packages(source)
    exports = exported_functions(source, packages)
    constructors = sorted(name for name in exports
                          if re.fullmatch(r"Mp\w+Create", name))
    if FORCED not in exports:
        raise SystemExit(f"{FORCED} is no longer an exported entry point.")
    # Tasks come from the package layout, not from the constructor names: the
    # metadata package also exports a Create entry point but is not a task.
    tasks = sorted(package.rsplit("/", 1)[-1] for package in packages
                   if re.fullmatch(r"mediapipe/tasks/c/(?:vision|text|audio)/"
                                   r"(?!core$)\w+", package))
    print(f"{len(packages)} linked packages, {len(exports)} exported functions, "
          f"{len(tasks)} tasks: {', '.join(tasks)}")

    flags = list(FLAGS)
    flags.extend(f"--linkopt=-Wl,-u,_{name}" for name in [*constructors, FORCED])
    if args.cpu_only:
        flags.append("--define=MEDIAPIPE_DISABLE_GPU=1")
    else:
        # MediaPipe registers rules_cc before apple_support. Bazel 7 otherwise
        # selects the generic C++ toolchain, which cannot compile objc_library.
        # This canonical label belongs to the pinned Bazel/apple_support setup.
        flags.extend([
            "--platforms=@build_bazel_apple_support//platforms:macos_arm64",
            "--extra_toolchains=@@apple_support~~apple_cc_configure_extension~local_config_apple_cc_toolchains//:all",
        ])
        flags.extend(f"--copt=-D{name}={OBJC_PREFIX}_{name}"
                     for name in OBJC_IDENTIFIERS)
    opencv, opencv_configuration = build_opencv(args.opencv_root.resolve())
    run(["bazelisk", f"--output_user_root={args.bazel_cache.resolve()}",
         "build", *flags, f"--override_repository=macos_opencv={opencv}", TARGET], source)
    built = source / "bazel-bin/mediapipe/tasks/c" / LIBRARY
    if not args.cpu_only:
        verify_objc_namespace(built)
    exported = {name.lstrip("_") for name in
                capture(["xcrun", "nm", "-gjU", str(built)]).splitlines()}
    missing = sorted(exports - exported)
    if missing:
        raise SystemExit(f"Missing C API exports in {built}: {missing}")
    library = ctypes.CDLL(str(built))
    for name in exports:
        getattr(library, name)  # Reject the upstream target's empty C API build.
    dependencies = capture(["otool", "-L", str(built)]).splitlines()[2:]
    for dependency in dependencies:
        name = dependency.strip().split(" (", 1)[0]
        if not name.startswith(("/System/Library/", "/usr/lib/")):
            raise SystemExit(f"Non-system dynamic dependency: {name}")

    output = PACKAGE / "build/native/tasks"
    if args.output_dir is not None:
        output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # The upstream library's install name is bare; these isolated native tests
    # point dyld at it. Flutter/Dart rewrite the ID when bundling.
    delegates = ["cpu"] if args.cpu_only else ["cpu", "gpu"]
    for task, smoke_source, model in SMOKES:
        smoke = output / f"native_smoke_{task}"
        run(["xcrun", "clang++", "-std=c++17", "-I", str(source),
             str(PACKAGE / smoke_source), str(built), "-o", str(smoke)])
        for delegate in delegates:
            result = subprocess.run(
                [str(smoke), str(PACKAGE / model),
                 str(PACKAGE / "test/fixtures/face_detection/landmark-ex1.jpg"),
                 delegate],
                env={**os.environ, "DYLD_LIBRARY_PATH": str(built.parent)},
                capture_output=True, text=True,
            )
            log = result.stdout + result.stderr
            (output / f"smoke_{task}_{delegate}.log").write_text(log)
            print(log, end="", flush=True)
            result.check_returncode()
            if delegate == "gpu" and "Created TensorFlow Lite delegate for Metal." not in log:
                raise SystemExit(
                    f"{task} GPU smoke did not confirm Metal delegate creation; "
                    "refusing CPU fallback.")
    destination = output / LIBRARY
    temporary = output / f"{LIBRARY}.tmp"
    shutil.copyfile(built, temporary)
    temporary.replace(destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    manifest = dict(
        source=SOURCE, revision=REVISION, version="1.0.0",
        target=TARGET, flags=flags, platform="macos", architecture="arm64",
        delegates=delegates, tasks=tasks, packages=packages,
        exported_functions=sorted(exports),
        opencv_revision=OPENCV_REVISION, opencv_configuration=opencv_configuration,
        sha256=digest, bytes=destination.stat().st_size,
        bazel_version=(source / ".bazelversion").read_text().strip(),
        xcode=capture(["xcodebuild", "-version"]),
        clang=capture(["xcrun", "clang", "--version"]),
    )
    manifest_path = output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    # Prepare a reviewable release artifact; this tool never uploads anything.
    archive = output / "mediapipe-vision-1.0.0-macos-arm64.tar.gz"
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
