"""Copy Google's hand and pose drawing edges into Dart, indices unchanged.

The face topology is emitted by `generate_face_landmarker_reference.py`; this
does the same for the two landmark tasks so overlays never hand-copy an edge
list. Run it in the pinned official environment:

    build/codex-tmp/gpu-reference-env/bin/python \
        packages/mediapipe-task-vision/tool/generate_landmark_connections.py
"""
from pathlib import Path
import shutil
import subprocess

import mediapipe as mp
from mediapipe.tasks.python.vision.hand_landmarker import HandLandmarksConnections
from mediapipe.tasks.python.vision.pose_landmarker import PoseLandmarksConnections

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.0.0'

GROUPS = (
    ('HandLandmarkConnections', 'HandLandmarksConnections', HandLandmarksConnections, {
        'all': 'HAND_CONNECTIONS',
        'palm': 'HAND_PALM_CONNECTIONS',
        'thumb': 'HAND_THUMB_CONNECTIONS',
        'indexFinger': 'HAND_INDEX_FINGER_CONNECTIONS',
        'middleFinger': 'HAND_MIDDLE_FINGER_CONNECTIONS',
        'ringFinger': 'HAND_RING_FINGER_CONNECTIONS',
        'pinkyFinger': 'HAND_PINKY_FINGER_CONNECTIONS',
    }),
    ('PoseLandmarkConnections', 'PoseLandmarksConnections', PoseLandmarksConnections, {
        'all': 'POSE_LANDMARKS',
    }),
)


def main():
    assert mp.__version__ == VERSION, mp.__version__
    lines = [
        '// Copyright 2023 The MediaPipe Authors.',
        '// Licensed under the Apache License, Version 2.0.',
        f'// Generated from MediaPipe v{VERSION} Hand/PoseLandmarksConnections.',
        '// Regenerate: tool/generate_landmark_connections.py',
        '',
        '/// Official hand and pose drawing edges, in the original index order.',
        'library;',
    ]
    for dart_name, upstream_name, source, groups in GROUPS:
        lines.extend([
            '',
            f'/// Official edges from {upstream_name}.',
            f'abstract final class {dart_name} {{',
        ])
        for name, attribute in groups.items():
            edges = getattr(source, attribute)
            lines.extend([
                f'  /// Official {attribute} ({len(edges)} edges).',
                f'  static const List<(int, int)> {name} = [',
                *(f'    ({edge.start}, {edge.end}),' for edge in edges),
                '  ];',
            ])
        lines.append('}')
    lines.append('')
    output = ROOT / 'lib/src/interface/landmark_connections.dart'
    output.write_text('\n'.join(lines))
    # Keep the checked-in file in the repository's format, so regenerating it
    # never fails `make check_format`.
    subprocess.run([shutil.which('dart') or 'dart', 'format', str(output)],
                   check=True, cwd=ROOT)
    print(f'Wrote {output}')


if __name__ == '__main__':
    main()
