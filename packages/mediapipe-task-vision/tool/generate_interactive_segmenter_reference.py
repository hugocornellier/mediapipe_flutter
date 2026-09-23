"""Generate masks and ABI facts through Google's unmodified Python 1.0.1 API.

The checked-in fixtures come from the macOS arm64 wheel. The Linux x64 desktop
job regenerates them in place with the pinned Linux wheel, whose library the
package bundles there, because CPU results drift between hosts.
Use a separate environment from the face-task reference environment (1.0.0).
--python-package-root may point at an extracted, checksum-verified 1.0.1 wheel.
Ordinary Dart tests need neither Python nor network access for their fixtures.
"""
import argparse
import ctypes
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import time

from prepare_interactive_segmenter import PACKAGE, LIBRARY_SHA256, MODEL_SHA256


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', type=Path)
    args = parser.parse_args()
    if args.python_package_root:
        sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks.python.vision import interactive_segmenter as api
    from mediapipe.tasks.python.core.base_options_c import MpBaseOptionsC

    assert mp.__version__ == '1.0.1', mp.__version__
    host = (platform.system(), platform.machine().lower())
    if host == ('Darwin', 'arm64'):
        library, library_sha256 = 'libmediapipe.dylib', LIBRARY_SHA256
    elif host in (('Linux', 'x86_64'), ('Linux', 'amd64')):
        from cpu_reference import wheel_pin
        library, library_sha256 = 'libmediapipe.so', wheel_pin('linux/x64')[2]
    else:
        raise SystemExit('The stateful API is pinned for macOS arm64 and Linux x64.')
    library = Path(mp.__file__).parent / 'tasks/c' / library
    assert digest(library.read_bytes()) == library_sha256
    model = PACKAGE / 'models/interactive_segmentation.task'
    assert digest(model.read_bytes()) == MODEL_SHA256
    fixtures = PACKAGE / 'test/fixtures/interactive_segmentation'
    photo = fixtures / 'cats_and_dogs.jpg'
    source = mp.Image.create_from_file(str(photo))
    # Small odd-width input for exact buffer/stride comparisons across wrappers.
    pixels = np.ascontiguousarray(source.numpy_view()[::4, ::4, :3][:, :299])
    (fixtures / 'animals-299x150.rgb').write_bytes(pixels.tobytes())
    raw = mp.Image(image_format=mp.ImageFormat.SRGB, data=pixels)
    rgba = mp.Image(image_format=mp.ImageFormat.SRGBA, data=np.concatenate(
        [pixels, np.full((*pixels.shape[:2], 1), 255, dtype=np.uint8)], axis=2))
    blank = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.zeros_like(pixels))

    def stroke(mode, points, completed=True):
        return {'brush_mode': mode, 'points': points, 'is_completed': completed}
    cat = stroke('positive', [[.27, .8]])
    dog = stroke('positive', [[.66, .55]])
    partial = stroke('positive', [[.66, .55], [.65, .65]], False)
    negative = stroke('negative', [[.42, .6]])
    lasso = stroke('lasso', [[.52, .2], [.78, .2], [.78, .98], [.52, .98], [.52, .2]])
    scenarios = [
        ('file-cat', 'file', True, [cat]),
        ('raw-dog', 'rgb', True, [dog]),
        ('raw-repeat', 'rgb', False, [dog]),
        ('raw-partial', 'rgb', False, [partial]),
        ('raw-two-positive', 'rgb', False, [dog, cat]),
        ('raw-negative', 'rgb', False, [dog, negative]),
        ('raw-lasso', 'rgb', False, [lasso]),
        ('raw-undo', 'rgb', False, [dog]),
        ('rgba-cat', 'rgba', True, [cat]),
        ('blank', 'blank', True, [dog]),
        ('replaced-image', 'rgb', True, [dog]),
    ]
    images = {'file': source, 'rgb': raw, 'rgba': rgba, 'blank': blank}
    report = {'runtime': 'mediapipe==1.0.1', 'delegate': 'CPU',
              'library_sha256': library_sha256, 'model_sha256': MODEL_SHA256,
              'image': {'file': photo.name, 'sha256': digest(photo.read_bytes()),
                        'source': 'https://storage.googleapis.com/mediapipe-assets/cats_and_dogs.jpg'},
              'raw': {'file': 'animals-299x150.rgb', 'sha256': digest(pixels.tobytes()),
                      'width': raw.width, 'height': raw.height,
                      'derivation': 'Official JPEG RGB decode, [::4, ::4, :3][:, :299]'},
              'cases': []}
    options = api.InteractiveSegmenterOptions(mp.tasks.BaseOptions(
        model_asset_path=str(model), delegate=mp.tasks.BaseOptions.Delegate.CPU))
    with api.InteractiveSegmenter.create_from_options(options) as task:
        for name, kind, set_image, strokes in scenarios:
            image = images[kind]
            t = time.perf_counter()
            if set_image:
                task.set_image(image)
            set_ms = (time.perf_counter() - t) * 1000 if set_image else None
            native_strokes = [api.Stroke(
                getattr(api.BrushMode, s['brush_mode'].upper()),
                [api.StrokePoint(*p) for p in s['points']], s['is_completed']) for s in strokes]
            t = time.perf_counter()
            result = task.segment(native_strokes)
            mask = np.ascontiguousarray(result.numpy_view(), dtype='<f4')
            assert mask.shape == (image.height, image.width, 1)
            assert np.isfinite(mask).all() and mask.min() >= 0 and mask.max() <= 1
            data = mask.tobytes()
            filename = f'{name}.f32.gz'
            (fixtures / filename).write_bytes(gzip.compress(data, mtime=0))
            report['cases'].append({'name': name, 'input': kind, 'set_image': set_image,
                'strokes': strokes, 'width': image.width, 'height': image.height,
                'mask': filename, 'sha256': digest(data),
                'foreground_pixels': int((mask > .5).sum()), 'mean': float(mask.mean()),
                'set_image_ms': set_ms, 'segment_and_copy_ms': (time.perf_counter()-t)*1000})
            print(name, report['cases'][-1]['foreground_pixels'], flush=True)
    report['abi'] = {
        cls.__name__: {'size': ctypes.sizeof(cls), 'alignment': ctypes.alignment(cls),
                      'offsets': {f[0]: getattr(cls, f[0]).offset for f in cls._fields_}}
        for cls in (MpBaseOptionsC, api.InteractiveSegmenterOptionsC, api.MpStrokePointC,
                    api.MpStrokeC, api.MpStrokesC)}
    (fixtures / 'official_reference.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
