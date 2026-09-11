"""Prepare a deterministic public release from an already tested native archive.

Does not build, upload, or modify repository visibility. The output directory
contains the exact files to publish; local filesystem paths and archive owners
are excluded from the public metadata.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

from build_native import PACKAGE, REVISION, OPENCV_REVISION

NAME = "mediapipe-face-detector-1.0.0-macos-arm64.tar.gz"
TAG = "face-detector-v1.0.0-1"
REPOSITORY = "hugocornellier/mediapipe_flutter_native"


def prepare(source, destination):
    files = {}
    with tarfile.open(source, "r:gz") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or member.name in files:
                raise ValueError(f"Invalid archive member: {member.name}")
            if member.isdir() and member.name == "opencv-licenses":
                continue
            if not member.isfile() or not (
                member.name in ("libface_detector.dylib", "manifest.json", "LICENSE", "NOTICE")
                or (len(path.parts) == 2 and path.parts[0] == "opencv-licenses")
            ):
                raise ValueError(f"Unexpected archive member: {member.name}")
            files[member.name] = archive.extractfile(member).read()
    for required in ("LICENSE", "NOTICE", "opencv-licenses/LICENSE",
                     "opencv-licenses/CAROTENE_NOTICES"):
        if not files.get(required):
            raise ValueError(f"Missing license: {required}")
    manifest = json.loads(files["manifest.json"])
    library_hash = hashlib.sha256(files["libface_detector.dylib"]).hexdigest()
    if (manifest["revision"] != REVISION
            or manifest["opencv_revision"] != OPENCV_REVISION
            or manifest["platform"] != "macos" or manifest["architecture"] != "arm64"
            or manifest["sha256"] != library_hash
            or manifest["bytes"] != len(files["libface_detector.dylib"])):
        raise ValueError("Native artifact provenance/hash mismatch")
    manifest["opencv_configuration"] = [
        value for value in manifest["opencv_configuration"]
        if not value.startswith("-DCMAKE_INSTALL_PREFIX=")
    ]
    manifest["clang"] = manifest["clang"].splitlines()[0]
    manifest["release"] = TAG
    files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / NAME
    # Identical input bytes yield an identical archive, independent of local
    # filenames, timestamps, filesystem permissions, and Unix account names.
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as bundle:
                for name, content in sorted(files.items()):
                    member = tarfile.TarInfo(name)
                    member.size = len(content)
                    member.mode = 0o644
                    bundle.addfile(member, io.BytesIO(content))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (destination / "SHA256SUMS").write_text(f"{digest}  {NAME}\n")
    (destination / "manifest.json").write_bytes(files["manifest.json"])
    (destination / "README.md").write_text(f"""# MediaPipe native runtimes

Native runtime downloads maintained by Hugo Cornellier. This is an independent
distribution, not an official Google release. This repository hosts native
artifacts and their provenance; the Dart/Flutter wrapper is developed separately.

## Face Detector

- Release: `{TAG}`; macOS Apple Silicon (arm64), CPU image inference.
- MediaPipe v1.0.0: [{REVISION}](https://github.com/google-ai-edge/mediapipe/tree/{REVISION}).
- Static OpenCV 4.12.0: [{OPENCV_REVISION}](https://github.com/opencv/opencv/tree/{OPENCV_REVISION}).
- Official task graph, calculators, model preprocessing, and C API are unchanged.
- Runtime library: {len(files['libface_detector.dylib']):,} bytes. Only macOS system
  frameworks and libraries are required at runtime.
- The model is separate and is not included in these native downloads.

Download the versioned archive from [Releases](https://github.com/{REPOSITORY}/releases).
Verify it against the release's `SHA256SUMS` before use. `manifest.json` records
the exact source revisions, compiler versions, build flags, and library digest.
Rebuilds use a new release tag; published archive URLs are never reused.

The archive includes upstream MediaPipe and OpenCV licenses and notices.
Retain the applicable notices when redistributing the native library.
""")
    (destination / "RELEASE_NOTES.md").write_text(f"""Face Detector runtime for macOS arm64, CPU IMAGE mode.

MediaPipe v1.0.0 with static OpenCV 4.12.0; the official task pipeline is unchanged.
The archive includes the native library, source/build manifest, and third-party
licenses and notices. Models are distributed separately.

- Archive SHA-256: `{digest}`
- Library SHA-256: `{library_hash}`
- Library size: {len(files['libface_detector.dylib']):,} bytes

Validated against official MediaPipe Python reference outputs, native C ABI
checks, and real Flutter debug and release inference on macOS arm64.

Android, iOS, Intel macOS, and video/live-stream modes are not included.
""")
    print(json.dumps(dict(repository=REPOSITORY, tag=TAG, archive=str(output),
                          sha256=digest, library_sha256=library_hash,
                          bytes=output.stat().st_size), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=PACKAGE / "build/native" / NAME)
    parser.add_argument("--output", type=Path, default=PACKAGE / "build/releases" / TAG)
    args = parser.parse_args()
    prepare(args.input, args.output)


if __name__ == "__main__":
    main()
