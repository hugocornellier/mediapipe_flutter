"""Test a fresh Flutter consumer with no native source or build tools.

Default: download from the pinned public release. Before publishing, pass
--local-release to serve the identical pinned archive over loopback HTTP.
Only the URL in the isolated package copy changes; both digests stay pinned.
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
import tempfile
from threading import Thread

from test_flutter_macos import PACKAGE, test_app
from prepare_native_release import NAME


@contextmanager
def release_server(directory):
    requests = []

    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            super().do_GET()

    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(directory)))
    worker = Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/{NAME}", requests
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


def verify(root, local_url=None):
    packages = root / "packages"
    for name in ("mediapipe-core", "mediapipe-task-vision"):
        source = PACKAGE.parent / name
        target = packages / name
        target.mkdir(parents=True)
        shutil.copyfile(source / "pubspec.yaml", target / "pubspec.yaml")
        shutil.copytree(source / "lib", target / "lib")
    vision = packages / PACKAGE.name
    shutil.copytree(PACKAGE / "hook", vision / "hook")
    shutil.copyfile(PACKAGE / "sdk_downloads.dart", vision / "sdk_downloads.dart")
    pins = vision / "sdk_downloads.dart"
    if local_url:
        content, count = re.subn(r"url:\s*(?:'[^']*'\s*)+,", f"url: '{local_url}',",
                                pins.read_text())
        if count != 1:
            raise ValueError("Could not identify the single pinned release URL")
        pins.write_text(content)
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
    test_app(app=root / "app", package=vision, env=env)
    if (vision / "build/native").exists() or (vision / "tool").exists():
        raise RuntimeError("Consumer unexpectedly has access to native build inputs")
    if log.exists():
        raise RuntimeError(log.read_text())
    manifests = list((root / "app/.dart_tool/hooks_runner").rglob("manifest.json"))
    # Flutter/Dart may change their hook-cache layout; search .dart_tool as a
    # fallback while still requiring that the downloaded runtime was extracted.
    if not manifests:
        manifests = list((root / "app/.dart_tool").rglob("manifest.json"))
    if not any(json.loads(path.read_text()).get("release") == "face-detector-v1.0.0-1"
               for path in manifests):
        raise RuntimeError("No extracted release manifest found in the consumer cache")
    print("Prebuilt consumer passed: debug/release inference; no native build tools invoked.",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-release", type=Path,
                        help="Directory containing the pinned archive before publication")
    args = parser.parse_args()
    build = PACKAGE.parents[1] / "build"
    build.mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="prebuilt-consumer-", dir=build))
    if args.local_release:
        with release_server(args.local_release.resolve()) as (url, requests):
            verify(root, local_url=url)
            if not requests:
                raise RuntimeError("Cold consumer never requested the release archive")
            if any(path != "/" + NAME for path in requests):
                raise RuntimeError(f"Unexpected release requests: {requests}")
            print(f"Verified {len(requests)} unauthenticated archive download(s).", flush=True)
    else:
        verify(root)


if __name__ == "__main__":
    main()
