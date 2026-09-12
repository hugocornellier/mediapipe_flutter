"""Generate Face Landmarker goldens with Google's pinned Python wheel.

Uses the same verified photographs and independent runtime as the detector
goldens. Dart consumers need neither Python nor the native build toolchain.
Also copies Google's drawing connections without changing indices or order.
"""
import argparse
import dataclasses
import json
from pathlib import Path

import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.vision.face_landmarker import FaceLandmarksConnections
from mediapipe.tasks.python.vision.core.image_processing_options import ImageProcessingOptions

from generate_face_detector_reference import ROOT, FIXTURES, LIBRARY_SHA256, digest, gpu_image

MODEL = ROOT / "models/face_landmarker.task"
MODEL_SHA256 = "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delegate", choices=("cpu", "gpu"), default="cpu")
    parser.add_argument("--output-dir", type=Path,
                        help="Write references here without changing fixtures or topology")
    args = parser.parse_args()
    delegate = getattr(mp.tasks.BaseOptions.Delegate, args.delegate.upper())
    suffix = "_gpu" if args.delegate == "gpu" else ""
    assert mp.__version__ == "1.0.0"
    assert digest(MODEL) == MODEL_SHA256
    assert digest(__import__('pathlib').Path(mp.__file__).parent /
                  "tasks/c/libmediapipe.dylib") == LIBRARY_SHA256
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    raw = FIXTURES / "portrait-301x209.rgb"
    pixels = np.frombuffer(raw.read_bytes(), dtype=np.uint8).reshape(209, 301, 3)
    pair = np.ascontiguousarray(np.concatenate(
        [pixels[:, 60:240, :], pixels[:, 60:240, :]], axis=1))
    images = {}
    for entry in manifest["files"]:
        file = FIXTURES / entry["file"]
        assert digest(file) == entry["sha256"]
        images[file.name] = mp.Image.create_from_file(str(file))
    arrays = dict(rgb=pixels, rgba=np.concatenate(
        [pixels, np.full((209, 301, 1), 255, dtype=np.uint8)], axis=2),
        pair=pair, rotated=np.ascontiguousarray(np.rot90(pixels)),
        blank=np.zeros((209, 301, 3), dtype=np.uint8))
    images.update({name: mp.Image(
        image_format=mp.ImageFormat.SRGBA if name == 'rgba' else mp.ImageFormat.SRGB,
        data=data) for name, data in arrays.items()})
    cases = []
    for mode, num_faces, names in [
        (vision.RunningMode.IMAGE, 2, list(images)),
        (vision.RunningMode.VIDEO, 1, ['rgb', 'rgb', 'blank', 'rgb', 'rotated', 'rgb']),
        (vision.RunningMode.VIDEO, 2, ['pair', 'pair', 'blank', 'rgb', 'pair']),
    ]:
        options = vision.FaceLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL),
                delegate=delegate),
            running_mode=mode, num_faces=num_faces,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=True)
        with vision.FaceLandmarker.create_from_options(options) as task:
            frames = []
            for index, name in enumerate(names):
                image = images[name]
                if args.delegate == 'gpu':
                    image = gpu_image(image)
                rotation = 90 if name == 'rotated' else 0
                processing = ImageProcessingOptions(rotation_degrees=rotation)
                result = (task.detect(image, processing) if mode == vision.RunningMode.IMAGE
                          else task.detect_for_video(image, index * 33, processing))
                frames.append(dict(name=name, width=image.width, height=image.height,
                    rotation=rotation, timestamp_ms=index * 33 if mode == vision.RunningMode.VIDEO else None,
                    **dataclasses.asdict(result)))
                print(mode.name, num_faces, name, len(result.face_landmarks), 'face(s)', flush=True)
            cases.append(dict(mode=mode.name, num_faces=num_faces, frames=frames))
    output = args.output_dir.resolve() if args.output_dir else FIXTURES.parent / 'face_landmarker'
    output.mkdir(parents=True, exist_ok=True)
    (output / f'official{suffix}_reference.json').write_text(json.dumps(dict(
        runtime='mediapipe==1.0.0', delegate=args.delegate.upper(),
        source_revision='6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
        library_sha256=LIBRARY_SHA256, model_sha256=MODEL_SHA256,
        **({'input_conversion': 'RGB to RGBA with opaque alpha for Metal'}
           if args.delegate == 'gpu' else {}),
        raw_sha256=digest(raw), cases=cases),
        default=lambda value: value.tolist(), allow_nan=False, separators=(',', ':')) + '\n')

    # Generate the Dart topology from the official API rather than hand-copy it.
    if args.delegate == 'gpu' or args.output_dir:
        return
    connections = {
        'tessellation': 'TESSELATION', 'contours': 'CONTOURS',
        'leftIris': 'LEFT_IRIS', 'rightIris': 'RIGHT_IRIS',
    }
    dart = ['// Copyright 2023 The MediaPipe Authors.',
            '// Licensed under the Apache License, Version 2.0.',
            '// Generated from MediaPipe v1.0.0 FaceLandmarksConnections.',
            '// Regenerate: tool/generate_face_landmarker_reference.py', '',
            '/// Official mesh drawing edges, in the original landmark index order.',
            'abstract final class FaceLandmarkConnections {']
    for name, upstream in connections.items():
        edges = getattr(FaceLandmarksConnections, 'FACE_LANDMARKS_' + upstream)
        dart.extend([f'  /// Official {name} connections ({len(edges)} edges).',
                     f'  static const List<(int, int)> {name} = ['])
        dart.extend(f'    ({edge.start}, {edge.end}),' for edge in edges)
        dart.append('  ];')
    dart.extend(['}', ''])
    (ROOT / 'lib/src/interface/face_landmark_connections.dart').write_text('\n'.join(dart))


if __name__ == '__main__':
    main()
