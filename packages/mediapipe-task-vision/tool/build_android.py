"""Build a combined Android task runtime for CPU validation with an NDK overlay.

Tracked upstream task sources stay unchanged. A deterministic toolchain package
registers the NDK through the upstream-pinned rules_android_ndk repository rule.
The WORKSPACE addition, Android export-map selection, generated file hashes and
NDK version are recorded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import struct

from build_native import (PACKAGE, REPO, REVISION, SOURCE, TARGET, FORCED,
                          capture, run, linked_packages, exported_functions)

NDK_VERSION = '28.2.13676358'
OPENCV_SDK_SHA256 = 'fd7f2332331b4eb8b67e55137281cfb16823c9399d90deb9cfa3476783b99e35'
OVERLAY = 'codex_android_toolchain'
SYSTEM_LIBRARIES = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libz.so',
                    'libandroid.so', 'libjnigraphics.so', 'libmediandk.so',
                    'libEGL.so', 'libGLESv2.so', 'libGLESv3.so', 'libOpenSLES.so'}


def check_elf(path, abi, readelf):
    data = path.read_bytes()
    machine = 183 if abi == 'arm64-v8a' else 62
    if (data[:6] != b'\x7fELF\x02\x01' or
            struct.unpack_from('<HH', data, 16) != (3, machine)):
        raise ValueError(f'Expected a little-endian {abi} shared library: {path}')
    offset = struct.unpack_from('<Q', data, 32)[0]
    stride, count = struct.unpack_from('<HH', data, 54)
    loads = []
    for index in range(count):
        kind, _, file_offset, address, _, _, _, alignment = struct.unpack_from(
            '<IIQQQQQQ', data, offset + index * stride)
        if kind == 1:
            if alignment < 16384 or (address - file_offset) % 16384:
                raise ValueError(f'ELF LOAD segment does not support 16 KB pages: {path}')
            loads.append(alignment)
    if not loads:
        raise ValueError(f'Missing ELF LOAD segments: {path}')
    dynamic = capture([str(readelf), '-d', str(path)])
    needed = sorted(re.findall(r'\(NEEDED\).*?\[([^]]+)\]', dynamic))
    soname = re.findall(r'\(SONAME\).*?\[([^]]+)\]', dynamic)
    if soname != [path.name]:
        raise ValueError(f'Unexpected ELF SONAME in {path}: {soname}')
    return {'needed': needed, 'load_alignments': loads, 'soname': soname[0]}


def overlay(source, ndk, api):
    generated = {
        'BUILD.bazel': b'exports_files(["repositories.bzl"])\n',
        'repositories.bzl': (
            'load("@rules_android_ndk//:rules.bzl", "android_ndk_repository")\n\n'
            'def register_ndk():\n'
            '    android_ndk_repository(\n'
            '        name = "androidndk",\n'
            f'        path = {json.dumps(str(ndk))},\n'
            f'        api_level = {api},\n'
            '    )\n'
            '    native.bind(name = "android/crosstool", actual = "@androidndk//:toolchain")\n').encode(),
    }
    original = capture(['git', 'show', 'HEAD:WORKSPACE'], source) + '\n'
    pinned = original.replace('name = "android_opencv",',
                              f'name = "android_opencv",\n    sha256 = "{OPENCV_SDK_SHA256}",')
    addition = (f'\nload("//{OVERLAY}:repositories.bzl", "register_ndk")\n'
                'register_ndk()\n')
    workspace = source / 'WORKSPACE'
    if workspace.is_symlink() or workspace.read_text() not in (original, original + addition, pinned + addition):
        raise ValueError('Refusing unexpected upstream WORKSPACE edits')
    directory = source / OVERLAY
    if directory.exists():
        expected = set(generated)
        for path in directory.rglob('*'):
            relative = path.relative_to(directory).as_posix()
            if (path.is_symlink() or path.is_file()) and relative not in expected:
                raise ValueError(f'Unexpected Android overlay input: {path}')
    for name, content in generated.items():
        path = directory / name
        if path.is_symlink() or (path.exists() and path.read_bytes() != content):
            raise ValueError(f'Refusing edited Android overlay: {path}')
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_bytes(content)
    workspace.write_text(pinned + addition)
    build_path = 'mediapipe/tasks/c/BUILD'
    original_build = capture(['git', 'show', 'HEAD:' + build_path], source) + '\n'
    export_selection = (
        '"@platforms//os:android": [\n'
        '            "-Wl,-soname=libmediapipe.so",\n'
        '            "-Wl,--version-script=$(location :mediapipe_tasks_c_version_script.lds)",\n'
        '        ],\n'
        '        "@platforms//os:linux": [')
    patched_build = original_build.replace('"@platforms//os:linux": [', export_selection)
    build_file = source / build_path
    if (patched_build == original_build or build_file.is_symlink() or
            build_file.read_text() not in (original_build, patched_build)):
        raise ValueError('Refusing unexpected upstream task BUILD edits')
    build_file.write_text(patched_build)
    return {'path': OVERLAY,
            'files': {name: hashlib.sha256(content).hexdigest()
                      for name, content in sorted(generated.items())},
            'workspace_original_sha256': hashlib.sha256(original.encode()).hexdigest(),
            'workspace_sha256': hashlib.sha256(workspace.read_bytes()).hexdigest(),
            'workspace_addition': addition,
            'task_build_original_sha256': hashlib.sha256(original_build.encode()).hexdigest(),
            'task_build_sha256': hashlib.sha256(patched_build.encode()).hexdigest(),
            'android_link_selection': export_selection,
            'opencv_sdk_sha256': OPENCV_SDK_SHA256,
            'rules_archive_sha256': '89bf5012567a5bade4c78eac5ac56c336695c3bfd281a9b0894ff6605328d2d5'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--abi', choices=('arm64-v8a', 'x86_64'), default='arm64-v8a')
    parser.add_argument('--api', type=int, default=24)
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--source-dir', type=Path, default=REPO / 'build/codex-tmp/mediapipe-android')
    parser.add_argument('--bazel-cache', type=Path, default=REPO / 'build/codex-tmp/bazel')
    args = parser.parse_args()
    if args.jobs < 1:
        raise SystemExit('--jobs must be positive.')
    if platform.system() not in ('Darwin', 'Linux'):
        raise SystemExit('Android builds require a Linux or macOS host.')
    if args.api < 24:
        raise SystemExit('The Android runtime requires API 24 or newer.')
    ndk = args.ndk.resolve()
    properties = (ndk / 'source.properties').read_text()
    version = re.search(r'^Pkg.Revision\s*=\s*(\S+)\s*$', properties, re.MULTILINE)
    if version is None or version.group(1) != NDK_VERSION:
        raise SystemExit(f'Refusing an unpinned NDK; require {NDK_VERSION}.')
    source = args.source_dir.resolve()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        cached = REPO / 'build/codex-tmp/mediapipe-native'
        if cached.exists() and capture(['git', 'rev-parse', 'HEAD'], cached) == REVISION:
            run(['git', 'clone', '--no-hardlinks', str(cached), str(source)])
        else:
            run(['git', 'clone', '--depth', '1', '--branch', 'v1.0.0', SOURCE, str(source)])
    if capture(['git', 'rev-parse', 'HEAD'], source) != REVISION:
        raise SystemExit('Refusing unpinned MediaPipe source.')
    changed = capture(['git', 'diff', '--name-only', 'HEAD'], source).splitlines()
    if any(name not in ('WORKSPACE', 'mediapipe/tasks/c/BUILD') for name in changed):
        raise SystemExit('Refusing modified tracked MediaPipe source files.')
    bazel = ['bazelisk', f'--output_user_root={args.bazel_cache.resolve()}']
    receipt = overlay(source, ndk, args.api)
    for name in capture(['git', 'ls-files', '--others', '--exclude-standard'], source).splitlines():
        # Bazel itself creates its dependency lock file; it is not task source.
        if name != 'MODULE.bazel.lock' and not name.startswith(OVERLAY + '/'):
            raise SystemExit(f'Refusing unexpected untracked MediaPipe input: {name}')
    packages = linked_packages(source)
    exports = exported_functions(source, packages)
    constructors = sorted(name for name in exports if re.fullmatch(r'Mp\w+Create', name))
    config = 'android_arm64' if args.abi == 'arm64-v8a' else 'android'
    flags = [f'--config={config}', f'--cpu={args.abi}',
             f'--platforms=//third_party/android:{args.abi}',
             '--extra_toolchains=@androidndk//:all',
             '--crosstool_top=//external:android/crosstool',
             '--repo_env=HERMETIC_PYTHON_VERSION=3.12',
             # Android's upstream buffer pool requires GL types even for CPU
             # task graphs. Compile its normal GL internals; GPU is unvalidated.
             '--define=MEDIAPIPE_DISABLE_GPU=0', '-c', 'opt', '--strip=always', f'--jobs={args.jobs}',
             '--linkopt=-Wl,-z,max-page-size=16384',
             '--linkopt=-Wl,-z,start-stop-visibility=hidden']
    flags.extend(f'--linkopt=-Wl,-u,{name}' for name in [*constructors, FORCED])
    run([*bazel, 'build', *flags, TARGET], source)
    output_base = Path(capture([*bazel, 'info', '--repo_env=HERMETIC_PYTHON_VERSION=3.12',
                                'output_base'], source))
    built = source / 'bazel-bin/mediapipe/tasks/c/libmediapipe.so'
    clang = ndk / ('toolchains/llvm/prebuilt/' +
                   ('darwin-x86_64' if platform.system() == 'Darwin' else 'linux-x86_64'))
    listing = capture([str(clang / 'bin/llvm-nm'), '-D', '--defined-only', str(built)])
    symbols = {line.split()[-1].split('@')[0] for line in listing.splitlines()}
    if exports - symbols:
        raise SystemExit(f'Missing C API exports: {sorted(exports - symbols)}')
    unexpected = {name for name in symbols if not name.startswith('Mp') and name != 'VERS_1.0'}
    if unexpected:
        raise SystemExit(f'Unexpected internal exports: {sorted(unexpected)}')
    output = PACKAGE / f'build/native/android/{args.abi}'
    output.mkdir(parents=True, exist_ok=True)
    library = output / 'libmediapipe.so'
    shutil.copyfile(built, library)
    opencv = output_base / f'external/android_opencv/sdk/native/libs/{args.abi}/libopencv_java4.so'
    shutil.copyfile(opencv, output / opencv.name)
    triple = 'aarch64-linux-android' if args.abi == 'arm64-v8a' else 'x86_64-linux-android'
    cpp = clang / f'sysroot/usr/lib/{triple}/libc++_shared.so'
    shutil.copyfile(cpp, output / cpp.name)
    libraries = [library, output / opencv.name, output / cpp.name]
    elf = {path.name: check_elf(path, args.abi, clang / 'bin/llvm-readelf')
           for path in libraries}
    bundled = set(elf)
    for name, metadata in elf.items():
        missing = set(metadata['needed']) - SYSTEM_LIBRARIES - bundled
        if missing:
            raise SystemExit(f'Unbundled dependencies in {name}: {sorted(missing)}')
    for name in ['LICENSE', 'NOTICE']:
        shutil.copyfile(PACKAGE / 'third_party' / name, output / name)
    shutil.copyfile(output_base / 'external/android_opencv/LICENSE', output / 'OPENCV_LICENSE')
    shutil.copytree(output_base / 'external/android_opencv/sdk/etc/licenses',
                    output / 'opencv-licenses', dirs_exist_ok=True)
    shutil.copyfile(PACKAGE / 'third_party/OPENCV_CAROTENE_NOTICES',
                    output / 'opencv-licenses/CAROTENE_NOTICES')
    shutil.copyfile(ndk / 'NOTICE', output / 'NDK_NOTICE')
    manifest = {'source': SOURCE, 'revision': REVISION, 'version': '1.0.0',
                'target': TARGET, 'platform': 'android', 'abi': args.abi,
                'minimum_api': args.api, 'validation_delegates': ['cpu'],
                'gpu_internals_compiled': True, 'flags': flags,
                'ndk_version': NDK_VERSION, 'ndk_path': str(ndk), 'toolchain_overlay': receipt,
                'c_api_export_count': len(exports),
                'export_map_sha256': hashlib.sha256((source /
                    'mediapipe/tasks/c/mediapipe_tasks_c_version_script.lds').read_bytes()).hexdigest(),
                'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                'bytes': library.stat().st_size,
                'elf': elf,
                'dependencies': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in libraries[1:]},
                'tasks': sorted(p.rsplit('/', 1)[-1] for p in packages
                                if re.fullmatch(r'mediapipe/tasks/c/(vision|text|audio)/(?!core$)\w+', p)),
                'validation': 'Build/export checks only; Android inference has not been validated.'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Android candidate: {library}', flush=True)


if __name__ == '__main__':
    main()
