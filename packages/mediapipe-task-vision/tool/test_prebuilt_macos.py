"""Test a fresh Flutter consumer with no native source or build tools.

Default: download from the pinned public release. Before publishing, pass
--local-release to serve the identical pinned archive over loopback HTTP.
Only the URL in the isolated package copy changes; both digests stay pinned.
--tasks-runtime turns on core's copy of Google's macOS engine, which Face
Landmarker then runs on instead of its source build.
"""
import argparse
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from threading import Thread

from test_flutter_macos import PACKAGE, test_app
from prepare_native_release import RELEASE_TAGS

sys.path.insert(0, str(PACKAGE.parent / "mediapipe-core/tool"))
from consumer_packages import copy_package  # noqa: E402
from official_wheels import macos_engine  # noqa: E402

OFFICIAL_HOOKS = '''hooks:
  user_defines:
    mediapipe_core:
      tasks_runtime: true
    mediapipe_vision:
      tasks: [face_detector, face_landmarker]
'''


@contextmanager
def release_server(directory):
    requests = []
    names = {path.name for path in directory.glob('*.tar.gz')}
    if not names:
        raise ValueError('No release archive found')

    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            super().do_GET()

    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(directory)))
    worker = Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        yield {name: f"http://127.0.0.1:{server.server_port}/{name}" for name in names}, requests
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


def verify(root, local_urls=None, official=False):
    packages = root / "packages"
    for name in ("mediapipe-core", "mediapipe-task-vision"):
        copy_package(PACKAGE.parent / name, packages / name)
    vision = packages / PACKAGE.name
    if local_urls:
        replaced = set()
        def replace_url(match):
            url = ''.join(re.findall(r"'([^']*)'", match.group()))
            name = url.rsplit('/', 1)[-1]
            if name not in local_urls:
                return match.group()
            replaced.add(name)
            return f"url: '{local_urls[name]}',"
        # The face releases are vision's pins; Google's engine is core's.
        for pins in (vision / "sdk_downloads.dart",
                     packages / "mediapipe-core/lib/src/native_assets/tasks_runtime.dart"):
            pins.write_text(re.sub(r"url:\s*(?:'[^']*'\s*)+,", replace_url,
                                   pins.read_text()))
        if replaced != set(local_urls):
            raise ValueError("Could not identify the pinned candidate release URLs")
    # Trap accidental source builds while preserving the Flutter/Xcode tools
    # normally available to macOS app developers. No system tool is uninstalled.
    guards = root / "blocked-tools"
    guards.mkdir()
    log = root / "blocked-tools.log"
    for name in ("bazel", "bazelisk", "cmake", "ninja"):
        script = guards / name
        script.write_text('#!/bin/sh\necho "Unexpected native build tool: $0" >> '
                          '"$MEDIAPIPE_BLOCKED_TOOLS_LOG"\nexit 97\n')
        script.chmod(0o755)
    env = {**os.environ, "PATH": str(guards) + os.pathsep + os.environ["PATH"],
           "MEDIAPIPE_BLOCKED_TOOLS_LOG": str(log)}
    print(f"Fresh prebuilt consumer: {root}", flush=True)
    test_app(app=root / "app", package=vision, env=env,
             hooks=OFFICIAL_HOOKS if official else '')
    if (vision / "build/native").exists() or (vision / "tool").exists():
        raise RuntimeError("Consumer unexpectedly has access to native build inputs")
    if log.exists():
        raise RuntimeError(log.read_text())
    manifests = list((root / "app/.dart_tool/hooks_runner").rglob("manifest.json"))
    # Flutter/Dart may change their hook-cache layout; search .dart_tool as a
    # fallback while still requiring that the downloaded runtime was extracted.
    if not manifests:
        manifests = list((root / "app/.dart_tool").rglob("manifest.json"))
    contents = [json.loads(path.read_text()) for path in manifests]
    found = {manifest.get("release") for manifest in contents}
    expected = set(RELEASE_TAGS.values())
    if official:
        expected = {RELEASE_TAGS["face_detector"]}
        if not any(manifest.get("origin") == "official-pypi-wheel"
                   and manifest.get("sha256") == macos_engine()["library_sha256"]
                   for manifest in contents):
            raise RuntimeError("Missing the extracted official runtime manifest")
    if not expected.issubset(found):
        raise RuntimeError(f"Missing extracted face-task release manifests: {found}")
    print("Prebuilt consumer passed: debug/release inference; no native build tools invoked.",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-release", type=Path,
                        help="Directory containing the pinned archive before publication")
    parser.add_argument("--tasks-runtime", action="store_true",
                        help="Turn on core's macOS engine, which serves Face Landmarker")
    args = parser.parse_args()
    build = PACKAGE.parents[1] / "build"
    build.mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="prebuilt-consumer-", dir=build))
    if args.local_release:
        with release_server(args.local_release.resolve()) as (urls, requests):
            verify(root, local_urls=urls, official=args.tasks_runtime)
            if not requests:
                raise RuntimeError("Cold consumer never requested the release archive")
            if any(path.lstrip('/') not in urls for path in requests):
                raise RuntimeError(f"Unexpected release requests: {requests}")
            print(f"Verified {len(requests)} unauthenticated archive download(s).", flush=True)
    else:
        verify(root, official=args.tasks_runtime)


if __name__ == "__main__":
    main()
