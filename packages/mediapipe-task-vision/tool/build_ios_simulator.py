"""Cross-build the official CPU face tasks for an arm64 iOS simulator.

This produces local development artifacts. Run tool/test_ios_simulator.py to
verify inference inside Flutter; macOS cannot load simulator dylibs directly.
No upstream source is modified and no artifact is uploaded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil

from build_native import (
    PACKAGE, REPO, REVISION, SOURCE, OPENCV_REVISION, SYMBOLS,
    build_opencv, capture, run,
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path,
                        default=REPO / 'build/codex-tmp/mediapipe-native')
    parser.add_argument('--bazel-cache', type=Path,
                        default=REPO / 'build/codex-tmp/bazel')
    parser.add_argument('--opencv-root', type=Path,
                        default=REPO / 'build/codex-tmp')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This cross-build requires an Apple Silicon Mac with Xcode.')
    source = args.source_dir.resolve()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run(['git', 'clone', '--depth', '1', '--branch', 'v1.0.0', SOURCE, str(source)])
    if capture(['git', 'rev-parse', 'HEAD'], source) != REVISION:
        raise SystemExit('Refusing unpinned MediaPipe source.')
    if capture(['git', 'diff', '--name-only', 'HEAD'], source):
        raise SystemExit('Refusing modified MediaPipe source.')
    opencv, configuration = build_opencv(args.opencv_root.resolve(), ios_simulator=True)
    flags = [
        '--config=ios', '--cpu=ios_sim_arm64', '--ios_minimum_os=13.0',
        '--platforms=@build_bazel_apple_support//platforms:ios_sim_arm64',
        '--extra_toolchains=@@apple_support~~apple_cc_configure_extension~local_config_apple_cc_toolchains//:all',
        '-c', 'opt', '--strip=always', '--jobs=8',
        '--repo_env=HERMETIC_PYTHON_VERSION=3.12',
        '--define=MEDIAPIPE_DISABLE_GPU=1',
        '--linkopt=-Wl,-headerpad_max_install_names',
        '--linkopt=-Wl,-u,_MpFaceDetectorCreate',
        '--linkopt=-Wl,-u,_MpFaceLandmarkerCreate',
        '--linkopt=-Wl,-u,_MpImageCreateFromFile',
        '--linkopt=-Wl,-exported_symbol,_Mp*',
    ]
    # Build tasks separately: each link must retain its own C entry points.
    for task in ('face_detector', 'face_landmarker'):
        landmarker = task == 'face_landmarker'
        unused = 'MpFaceDetectorCreate' if landmarker else 'MpFaceLandmarkerCreate'
        task_flags = [flag for flag in flags if unused not in flag]
        target = f'//mediapipe/tasks/c/vision/{task}:lib{task}.dylib'
        run(['bazelisk', f'--output_user_root={args.bazel_cache.resolve()}',
             'build', *task_flags, f'--override_repository=ios_opencv={opencv}', target], source)
        built = source / f'bazel-bin/mediapipe/tasks/c/vision/{task}/lib{task}.dylib'
        build_info = capture(['xcrun', 'vtool', '-show-build', str(built)])
        if ('platform IOSSIMULATOR' not in build_info or
                capture(['xcrun', 'lipo', '-archs', str(built)]) != 'arm64'):
            raise SystemExit(f'Not an arm64 simulator dylib: {build_info}')
        exported = set(capture(['xcrun', 'nm', '-gjU', str(built)]).splitlines())
        symbols = [name.replace('MpFaceDetector', 'MpFaceLandmarker')
                   if landmarker else name for name in SYMBOLS]
        symbols.append('MpFaceLandmarkerDetectForVideo' if landmarker else 'MpFaceDetectorDetectForVideo')
        if not all('_' + symbol in exported for symbol in symbols):
            raise SystemExit(f'Missing C API exports in {built}')
        for dependency in capture(['otool', '-L', str(built)]).splitlines()[2:]:
            name = dependency.strip().split(' (', 1)[0]
            if not name.startswith(('/System/Library/', '/usr/lib/')):
                raise SystemExit(f'Non-system dependency: {name}')
        output = PACKAGE / f'build/native/ios-simulator/arm64/{task}'
        output.mkdir(parents=True, exist_ok=True)
        destination = output / built.name
        temporary = output / f'{built.name}.tmp'
        shutil.copyfile(built, temporary)
        temporary.replace(destination)
        manifest = dict(
            source=SOURCE, revision=REVISION, version='1.0.0', target=target,
            platform='ios', architecture='arm64', ios_sdk='iphonesimulator',
            minimum_os='13.0', delegates=['cpu'], flags=task_flags,
            opencv_revision=OPENCV_REVISION, opencv_configuration=configuration,
            sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
            bytes=destination.stat().st_size,
            bazel_version=(source / '.bazelversion').read_text().strip(),
            xcode=capture(['xcodebuild', '-version']), build_info=build_info,
            validation='Architecture/exports/dependencies checked; run Flutter simulator tests.',
        )
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        for name in ('LICENSE', 'NOTICE'):
            shutil.copyfile(PACKAGE / 'third_party' / name, output / name)
        licenses = output / 'opencv-licenses'
        shutil.copytree(opencv / 'share/licenses/opencv4', licenses, dirs_exist_ok=True)
        shutil.copyfile(args.opencv_root / 'opencv/LICENSE', licenses / 'LICENSE')
        shutil.copyfile(PACKAGE / 'third_party/OPENCV_CAROTENE_NOTICES', licenses / 'CAROTENE_NOTICES')
        print(f'Simulator artifact: {destination}', flush=True)


if __name__ == '__main__':
    main()
