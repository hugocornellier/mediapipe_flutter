"""Runs Face Landmarker's three models on LiteRT's CPU and GPU accelerators.

Inputs are realistic: the letterboxed portrait for the face detector, a face crop
around MediaPipe's own CPU landmarks for the landmark model, and those landmarks'
blendshape subset in image pixels for the blendshape model. GPU runs request the
GPU alone, so a model the accelerator cannot take fails instead of falling back
to CPU. Writes a JSON report; timings on a software GPU say nothing about speed.
"""
import argparse
import json
import math
import statistics
import sys
import time
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

import ai_edge_litert
from ai_edge_litert.compiled_model import CompiledModel
from ai_edge_litert.hardware_accelerator import HardwareAccelerator
from ai_edge_litert.options import GpuOptions, Options

# kLandmarksSubsetIdxs in upstream v1.0.0
# mediapipe/tasks/cc/vision/face_landmarker/face_blendshapes_graph.cc.
BLENDSHAPE_LANDMARKS = [
    0, 1, 4, 5, 6, 7, 8, 10, 13, 14, 17, 21, 33, 37, 39,
    40, 46, 52, 53, 54, 55, 58, 61, 63, 65, 66, 67, 70, 78, 80,
    81, 82, 84, 87, 88, 91, 93, 95, 103, 105, 107, 109, 127, 132, 133,
    136, 144, 145, 146, 148, 149, 150, 152, 153, 154, 155, 157, 158, 159, 160,
    161, 162, 163, 168, 172, 173, 176, 178, 181, 185, 191, 195, 197, 234, 246,
    249, 251, 263, 267, 269, 270, 276, 282, 283, 284, 285, 288, 291, 293, 295,
    296, 297, 300, 308, 310, 311, 312, 314, 317, 318, 321, 323, 324, 332, 334,
    336, 338, 356, 361, 362, 365, 373, 374, 375, 377, 378, 379, 380, 381, 382,
    384, 385, 386, 387, 388, 389, 390, 397, 398, 400, 402, 405, 409, 415, 454,
    466, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477,
]
MODELS = ('face_detector', 'face_landmarks_detector', 'face_blendshapes')
# MediaPipe's GPU graph runs these two on the GPU and keeps the blendshape model
# on XNNPACK; its GPU attempt is recorded, not required.
GPU_MODELS = ('face_detector', 'face_landmarks_detector')


def variants():
    return {
        'cpu': Options(hardware_accelerators=HardwareAccelerator.CPU),
        'gpu': Options(hardware_accelerators=HardwareAccelerator.GPU),
        'gpu_f32': Options(hardware_accelerators=HardwareAccelerator.GPU,
                           gpu_options=GpuOptions(enforce_f32=True)),
    }


def model_inputs(portrait, reference):
    image = Image.open(portrait).convert('RGB')
    width, height = image.size
    scale = 128 / max(width, height)
    small = image.resize((round(width * scale), round(height * scale)), Image.BILINEAR)
    letterbox = Image.new('RGB', (128, 128))
    letterbox.paste(small, ((128 - small.width) // 2, (128 - small.height) // 2))
    detector = np.asarray(letterbox, np.float32)[None] / 127.5 - 1

    points = np.asarray(json.loads(Path(reference).read_text())['landmarks'], np.float32)
    x, y = points[:, 0] * width, points[:, 1] * height
    side = 1.5 * max(x.max() - x.min(), y.max() - y.min())
    left, top = (x.min() + x.max() - side) / 2, (y.min() + y.max() - side) / 2
    box = tuple(round(v) for v in (left, top, left + side, top + side))
    crop = image.crop(box).resize((256, 256), Image.BILINEAR)
    landmarks = np.asarray(crop, np.float32)[None] / 255

    subset = np.stack([x[BLENDSHAPE_LANDMARKS], y[BLENDSHAPE_LANDMARKS]], axis=1)[None]
    feeds = {'face_detector': detector, 'face_landmarks_detector': landmarks,
             'face_blendshapes': subset}
    return {k: v.astype(np.float32) for k, v in feeds.items()}, box[2] - box[0], (width, height)


def run(path, options, feed, repeats):
    model = CompiledModel.from_file(str(path), options=options)
    try:
        key = next(iter(model.get_signature_list()))
        signature = model.get_signature_list()[key]
        (input_name,) = signature['inputs']
        inputs = {input_name: model.create_input_buffer_by_name(key, input_name)}
        inputs[input_name].write(feed)
        outputs = {name: model.create_output_buffer_by_name(key, name)
                   for name in signature['outputs']}
        begin = time.perf_counter()
        model.run_by_name(key, inputs, outputs)
        first = (time.perf_counter() - begin) * 1000
        times = []
        for _ in range(repeats):
            begin = time.perf_counter()
            model.run_by_name(key, inputs, outputs)
            times.append((time.perf_counter() - begin) * 1000)
        details = model.get_output_tensor_details(key)
        values = {name: np.asarray(outputs[name].read(math.prod(details[name]['shape']), np.float32))
                  .reshape(details[name]['shape']) for name in signature['outputs']}
        return {'fully_accelerated': model.is_fully_accelerated(), 'first_ms': round(first, 2),
                'median_ms': round(statistics.median(times), 3)}, values
    finally:
        if hasattr(model, 'close'):  # absent before ai-edge-litert 2.2
            model.close()


def sigmoid(v):
    return 1 / (1 + np.exp(-v))


def compare(name, cpu, other, crop_side, size):
    result = {'max_abs': {k: float(np.max(np.abs(cpu[k] - other[k]))) for k in cpu}}
    if name == 'face_detector':
        a, b = sigmoid(cpu['classificators'].ravel()), sigmoid(other['classificators'].ravel())
        best = int(np.argmax(a))
        result.update(
            best_anchor_same=best == int(np.argmax(b)),
            best_score=[round(float(a[best]), 5), round(float(b[best]), 5)],
            best_box_max_abs_input_px=float(np.max(np.abs(
                cpu['regressors'][0, best, :4] - other['regressors'][0, best, :4]))))
    elif name == 'face_landmarks_detector':
        a, b = cpu['Identity'].reshape(478, 3), other['Identity'].reshape(478, 3)
        to_image = crop_side / 256
        dx = np.abs(a[:, 0] - b[:, 0]) * to_image / size[0]
        dy = np.abs(a[:, 1] - b[:, 1]) * to_image / size[1]
        result.update(
            landmark_xy_max_abs_normalized=round(float(max(dx.max(), dy.max())), 6),
            landmark_xy_mean_abs_normalized=round(float((dx.mean() + dy.mean()) / 2), 6),
            landmark_z_max_abs_crop_px=round(float(np.max(np.abs(a[:, 2] - b[:, 2]))), 4),
            presence=[round(float(sigmoid(cpu['Identity_1']).item()), 5),
                      round(float(sigmoid(other['Identity_1']).item()), 5)])
    else:
        (key,) = cpu
        result.update(score_max_abs=round(float(np.max(np.abs(cpu[key] - other[key]))), 6))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--task', required=True, help='face_landmarker.task bundle')
    parser.add_argument('--portrait', required=True)
    parser.add_argument('--reference', required=True, help='JSON with MediaPipe CPU landmarks')
    parser.add_argument('--out', required=True, help='report path')
    parser.add_argument('--repeats', type=int, default=20)
    args = parser.parse_args()

    models = Path(args.out).parent / 'models'
    with zipfile.ZipFile(args.task) as bundle:
        bundle.extractall(models)
    feeds, crop_side, size = model_inputs(args.portrait, args.reference)
    report = {'litert': ai_edge_litert.__version__, 'models': {}}
    for name in MODELS:
        entry = report['models'][name] = {}
        values = {}
        for variant, options in variants().items():
            try:
                entry[variant], values[variant] = run(models / f'{name}.tflite', options,
                                                      feeds[name], args.repeats)
            except Exception as error:  # a refused accelerator raises; record why
                entry[variant] = {'error': f'{type(error).__name__}: {error}'}
        for variant in ('gpu', 'gpu_f32'):
            if 'cpu' in values and variant in values:
                entry[variant]['vs_cpu'] = compare(name, values['cpu'], values[variant],
                                                   crop_side, size)
        for variant, result in entry.items():
            print(f'{name} {variant}: {json.dumps(result)}', flush=True)
    report['cpu_ran_all_models'] = all('error' not in report['models'][n]['cpu'] for n in MODELS)
    report['gpu_ran_detector_and_landmarks_fully_accelerated'] = all(
        report['models'][n][v].get('fully_accelerated') is True
        for n in GPU_MODELS for v in ('gpu', 'gpu_f32'))
    Path(args.out).write_text(json.dumps(report, indent=2) + '\n')
    passed = (report['cpu_ran_all_models']
              and report['gpu_ran_detector_and_landmarks_fully_accelerated'])
    print(f"VERDICT: CPU ran all models: {report['cpu_ran_all_models']}; GPU ran the detector "
          f"and landmark models fully accelerated: "
          f"{report['gpu_ran_detector_and_landmarks_fully_accelerated']}", flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
