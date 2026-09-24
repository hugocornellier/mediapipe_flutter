"""Does the installed MediaPipe's GPU delegate run here? (scratch probe)

The 1.1.0 nightly Windows DLL contains Dawn with a D3D12 backend, which 1.0.0
lacks. This runs Face Detector, Face Landmarker and Hand Landmarker on CPU and
on Delegate.GPU, one process per case, records the outcome and GPU-related log
lines, and compares GPU landmarks with CPU.

    python -B tool/windows_nightly_gpu_probe.py <output dir>
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
STORAGE = 'https://storage.googleapis.com/mediapipe-models/'
MODELS = {
    'face_detector': (STORAGE + 'face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite',
                      'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f'),
    'face_landmarker': (STORAGE + 'face_landmarker/face_landmarker/float16/1/face_landmarker.task',
                        '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff'),
    'hand_landmarker': (STORAGE + 'hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task',
                        'fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1'),
}
IMAGES = {'face_detector': 'face_detection/landmark-ex1.jpg',
          'face_landmarker': 'face_detection/landmark-ex1.jpg',
          'hand_landmarker': 'landmark_tasks/thumb_up.jpg'}
KEYWORDS = ('error', 'failed', 'check failed', 'not supported', 'disabled', 'webgpu', 'dawn', 'adapter',
            'd3d12', 'dxil', 'dxcompiler', 'delegate', 'accelerator', 'gpu', 'warp', 'basic render')


def case(task, delegate, model, image, output):
    import mediapipe as mp
    from mediapipe.tasks.python import vision
    base = mp.tasks.BaseOptions(model_asset_path=model,
                                delegate=getattr(mp.tasks.BaseOptions.Delegate, delegate.upper()))
    loaded = mp.Image.create_from_file(image)
    if task == 'face_detector':
        with vision.FaceDetector.create_from_options(vision.FaceDetectorOptions(base_options=base)) as t:
            result = t.detect(loaded)
        points = [[k.x, k.y] for d in result.detections for k in d.keypoints]
        extra = dict(detections=len(result.detections),
                     score=result.detections[0].categories[0].score if result.detections else None)
    elif task == 'face_landmarker':
        options = vision.FaceLandmarkerOptions(base_options=base, output_face_blendshapes=True)
        with vision.FaceLandmarker.create_from_options(options) as t:
            result = t.detect(loaded)
        points = [[p.x, p.y, p.z] for face in result.face_landmarks for p in face]
        extra = dict(faces=len(result.face_landmarks),
                     blendshapes=len(result.face_blendshapes[0]) if result.face_blendshapes else 0)
    else:
        with vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(base_options=base)) as t:
            result = t.detect(loaded)
        points = [[p.x, p.y, p.z] for hand in result.hand_landmarks for p in hand]
        extra = dict(hands=len(result.hand_landmarks))
    Path(output).write_text(json.dumps(dict(version=mp.__version__, points=points, **extra)))


def main(output):
    output.mkdir(parents=True, exist_ok=True)
    models = output / 'models'
    models.mkdir(exist_ok=True)
    import mediapipe
    library = next((Path(mediapipe.__file__).parent / 'tasks/c').glob('libmediapipe.*'))
    report = dict(version=mediapipe.__version__, library=library.name,
                  library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(), cases={})
    for task, (url, sha) in MODELS.items():
        model = models / url.rsplit('/', 1)[1]
        if not model.exists():
            model.write_bytes(urllib.request.urlopen(url, timeout=300).read())
        assert hashlib.sha256(model.read_bytes()).hexdigest() == sha, task
        for delegate in ('cpu', 'gpu'):
            result_file = output / f'{task}-{delegate}.json'
            try:
                run = subprocess.run([sys.executable, '-B', __file__, '--case', task, delegate, str(model),
                                      str(PACKAGE / 'test/fixtures' / IMAGES[task]), str(result_file)],
                                     capture_output=True, text=True, timeout=600)
                code, text = run.returncode, run.stdout + run.stderr
            except subprocess.TimeoutExpired as error:
                code, text = 'timeout', str(error.stdout or '') + str(error.stderr or '')
            (output / f'{task}-{delegate}.log').write_text(text, encoding='utf-8')
            lines = [line.strip()[:220] for line in text.splitlines()
                     if any(k in line.lower() for k in KEYWORDS)]
            entry = dict(exit=code, log_lines=lines[:12])
            if code == 0 and result_file.exists():
                entry.update(json.loads(result_file.read_text()))
            report['cases'][f'{task}/{delegate}'] = entry
        cpu, gpu = report['cases'][f'{task}/cpu'], report['cases'][f'{task}/gpu']
        if cpu.get('points') and gpu.get('points') and len(cpu['points']) == len(gpu['points']):
            gpu['max_delta_vs_cpu'] = max(abs(a - b) for p, q in zip(cpu['points'], gpu['points'])
                                          for a, b in zip(p, q))
    for entry in report['cases'].values():
        entry.pop('points', None)
    (output / 'report.json').write_text(json.dumps(report, indent=1) + '\n', encoding='utf-8')
    lines = [f"MediaPipe {report['version']}, {library.name} {report['library_sha256'][:16]}, {output.name}",
             '', '| case | exit | result | GPU vs CPU | first GPU-related log line |',
             '| --- | --- | --- | --- | --- |']
    for name, entry in report['cases'].items():
        result = {k: v for k, v in entry.items() if k not in ('exit', 'log_lines', 'version', 'max_delta_vs_cpu')}
        lines.append(f"| {name} | {entry['exit']} | {result} | {entry.get('max_delta_vs_cpu', '')} | "
                     f"{(entry['log_lines'] or [''])[-1].replace('|', '/')} |")
    (output / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('\n'.join(lines))


if __name__ == '__main__':
    if sys.argv[1] == '--case':
        case(*sys.argv[2:7])
    else:
        main(Path(sys.argv[1]).resolve())
