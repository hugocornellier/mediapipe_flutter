"""Regenerate reviewed goldens with Google's official macOS arm64 Python API.

Run from the package root in a Python 3.12 venv with mediapipe==1.0.0.
The Dart tests consume the checked-in JSON; they do not need Python.
"""
import argparse
import dataclasses
import hashlib
import json
from pathlib import Path
import platform

import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.vision.core.image_processing_options import ImageProcessingOptions

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures/face_detection"
MODEL = ROOT / "models/blaze_face_short_range.tflite"
MODEL_SHA256 = "b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f"
LIBRARY_SHA256 = "aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def gpu_image(image):
    """Apple's GPU upload requires RGBA; preserve RGB values and add alpha."""
    if image.image_format != mp.ImageFormat.SRGB:
        return image
    pixels = image.numpy_view()
    return mp.Image(image_format=mp.ImageFormat.SRGBA, data=np.concatenate(
        [pixels, np.full((*pixels.shape[:2], 1), 255, dtype=np.uint8)], axis=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delegate", choices=("cpu", "gpu"), default="cpu")
    parser.add_argument("--output-dir", type=Path,
                        help="Write independent references here without changing fixtures")
    args = parser.parse_args()
    output = args.output_dir.resolve() if args.output_dir else FIXTURES
    output.mkdir(parents=True, exist_ok=True)
    delegate = getattr(mp.tasks.BaseOptions.Delegate, args.delegate.upper())
    suffix = "_gpu" if args.delegate == "gpu" else ""
    assert mp.__version__ == "1.0.0", mp.__version__
    assert platform.system() == "Darwin" and platform.machine() == "arm64"
    assert digest(MODEL) == MODEL_SHA256
    library = Path(mp.__file__).parent / "tasks/c/libmediapipe.dylib"
    assert digest(library) == LIBRARY_SHA256
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    cases = []
    options = vision.FaceDetectorOptions(
        base_options=mp.tasks.BaseOptions(
            model_asset_path=str(MODEL),
            delegate=delegate,
        ),
        min_detection_confidence=0.5,
        min_suppression_threshold=0.3,
    )
    with vision.FaceDetector.create_from_options(options) as detector:
        def record(name, image, *, rotation=0, file=None, raw=None):
            if args.delegate == "gpu":
                image = gpu_image(image)
            result = detector.detect(
                image, ImageProcessingOptions(
                    rotation_degrees=rotation
                )
            )
            case = dict(
                name=name, width=image.width, height=image.height,
                rotation_degrees=rotation, **dataclasses.asdict(result)
            )
            if file is not None:
                case.update(file=file.name, sha256=digest(file))
            if raw is not None:
                case.update(raw=raw.name, sha256=digest(raw))
            cases.append(case)
            print(name, len(result.detections), "face(s)")
        for entry in manifest["files"]:
            file = FIXTURES / entry["file"]
            assert digest(file) == entry["sha256"]
            record(entry["file"], mp.Image.create_from_file(str(file)), file=file)

        # Decimate the official decoder's RGB pixels to a small, odd-width input.
        # The resulting bytes are checked in so no test depends on a JPEG decoder.
        pixels = mp.Image.create_from_file(
            str(FIXTURES / "mesh-ex1.jpeg")
        ).numpy_view()[::20, ::20, :3].copy()
        raw = FIXTURES / "portrait-301x209.rgb"
        if args.output_dir:
            # A host comparison must use exactly the checked-in fixture bytes.
            assert raw.read_bytes() == pixels.tobytes(), "Raw fixture derivation changed"
        else:
            raw.write_bytes(pixels.tobytes())
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=pixels)
        record("rgb", image, raw=raw)
        rgba = np.concatenate(
            [pixels, np.full((*pixels.shape[:2], 1), 255, dtype=np.uint8)], axis=2
        )
        record("rgba", mp.Image(image_format=mp.ImageFormat.SRGBA, data=rgba), raw=raw)
        pair = np.ascontiguousarray(np.concatenate(
            [pixels[:, 60:240, :], pixels[:, 60:240, :]], axis=1
        ))
        record("rgb-pair", mp.Image(image_format=mp.ImageFormat.SRGB, data=pair), raw=raw)
        # Rotate input counterclockwise, then let MediaPipe correct it clockwise.
        record(
            "rgb-rotated", mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=np.ascontiguousarray(np.rot90(pixels)),
            ), rotation=90, raw=raw
        )
        record("blank", mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=np.zeros((480, 640, 3), dtype=np.uint8)
        ))

    reference = dict(
        runtime="mediapipe==1.0.0",
        source_revision="6d31f1ebc3284db74d211d62bdc4f0a0c29ea120",
        library_sha256=LIBRARY_SHA256,
        model_sha256=MODEL_SHA256,
        platform="macOS arm64", delegate=args.delegate.upper(), running_mode="IMAGE",
        min_detection_confidence=0.5, min_suppression_threshold=0.3,
        raw_derivation="mesh-ex1.jpeg official RGB decoder, [::20, ::20, :3]",
        **({"input_conversion": "RGB to RGBA with opaque alpha for Metal"}
           if args.delegate == "gpu" else {}),
        cases=cases,
    )
    (output / f"official{suffix}_reference.json").write_text(
        json.dumps(reference, indent=2, allow_nan=False) + "\n"
    )

    video_cases = []
    frames = [
        ("rgb", pixels, 0), ("rgb", pixels, 0),
        ("blank", np.zeros((209, 301, 3), dtype=np.uint8), 0),
        ("rgb-pair", pair, 0), ("rgb", pixels, 0),
        ("rgb-rotated", np.ascontiguousarray(np.rot90(pixels)), 90),
        ("rgb", pixels, 0),
    ]
    options.running_mode = vision.RunningMode.VIDEO
    with vision.FaceDetector.create_from_options(options) as detector:
        for index, (name, data, rotation) in enumerate(frames):
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=data)
            if args.delegate == "gpu":
                image = gpu_image(image)
            timestamp = index * 33
            result = detector.detect_for_video(image, timestamp,
                ImageProcessingOptions(rotation_degrees=rotation))
            case = dict(name=name, width=image.width, height=image.height,
                        timestamp_ms=timestamp, rotation_degrees=rotation,
                        **dataclasses.asdict(result))
            if name != "blank":
                case.update(raw=raw.name, sha256=digest(raw))
            video_cases.append(case)
            print("video", timestamp, name, len(result.detections), "face(s)")
    (output / f"official{suffix}_video_reference.json").write_text(json.dumps(
        {**reference, "running_mode": "VIDEO", "cases": video_cases},
        indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
