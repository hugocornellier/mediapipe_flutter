"""Which Holistic options field order does Google's compiled library read? (UP-005)

Google's Python ctypes declare the three pose thresholds before the hand
threshold; the public C header declares the hand threshold first. The probe
sets one threshold at a time to an extreme value and records what disappears
from pose.jpg, once with the Python order as shipped and once rearranged into
the header's order (what the Dart wrapper writes on macOS). Whichever
arrangement makes every option act on its own field is the order the library
reads.

Runs the pinned official wheel for this host in an isolated environment:
    python3 -B tool/holistic_threshold_order_probe.py --output <dir>
"""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import sys

MODEL_URL = ('https://storage.googleapis.com/mediapipe-models/'
             'holistic_landmarker/holistic_landmarker/float16/1/holistic_landmarker.task')
MODEL_SHA256 = 'e2dab61191e2dcd0a15f943d8e3ed1dce13c82dfa597b9dd39f562975a50c3f8'
SETTINGS = [('baseline', None, None),
            ('pose_detection', 'min_pose_detection_confidence', 0.9999),
            ('pose_suppression', 'min_pose_suppression_threshold', 0.9999),
            ('pose_presence', 'min_pose_landmarks_confidence', 1.0),
            ('hand', 'min_hand_landmarks_confidence', 1.0)]
# The effect of each setting when the library applies it to the field it names.
OWN_FIELD = {'pose_detection': 'pose gone', 'pose_suppression': 'unchanged',
             'pose_presence': 'pose gone', 'hand': 'hands gone'}
WHEEL = ('min_pose_detection_confidence', 'min_pose_suppression_threshold',
         'min_pose_landmarks_confidence', 'min_hand_landmarks_confidence')
HEADER = ('min_hand_landmarks_confidence', 'min_pose_detection_confidence',
          'min_pose_suppression_threshold', 'min_pose_landmarks_confidence')


def worker(model, image, arrangement):
    """Runs inside the pinned wheel's environment and prints one JSON result."""
    import mediapipe as mp
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.vision import holistic_landmarker as holistic

    fields = [name for name, *_ in holistic.MpHolisticLandmarkerOptionsC._fields_]
    if arrangement == 'header':
        original = holistic.MpHolisticLandmarkerOptionsC.from_c_options

        def header_order(*positional, **options):
            # Slot i of the wheel's struct receives the header's i-th threshold.
            values = [options[name] for name in HEADER]
            options.update(zip(WHEEL, values))
            return original(*positional, **options)
        holistic.MpHolisticLandmarkerOptionsC.from_c_options = header_order
    counts = {}
    for label, field, value in SETTINGS:
        options = vision.HolisticLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=model,
                                              delegate=mp.tasks.BaseOptions.Delegate.CPU),
            **({field: value} if field else {}))
        with vision.HolisticLandmarker.create_from_options(options) as task:
            result = task.detect(mp.Image.create_from_file(image))
        counts[label] = dict(pose=len(result.pose_landmarks),
                             left_hand=len(result.left_hand_landmarks),
                             right_hand=len(result.right_hand_landmarks))
    print(json.dumps(dict(version=mp.__version__, python_fields=fields, counts=counts)))


def effect(observed, baseline):
    if observed == baseline:
        return 'unchanged'
    if observed['pose'] == 0:
        return 'pose gone'
    if observed['pose'] and not observed['left_hand'] and not observed['right_hand']:
        return 'hands gone'
    return 'other'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--worker', nargs=3, metavar=('MODEL', 'IMAGE', 'ARRANGEMENT'))
    parser.add_argument('--python', type=Path, help='use this environment instead of installing')
    args = parser.parse_args()
    if args.worker:
        return worker(*args.worker)

    from cpu_reference import host_target, install, wheel_pin
    from test_desktop import PACKAGE, digest, download

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    target = host_target()
    _, wheel_sha, library_sha, version = wheel_pin(target)
    model = output / 'holistic_landmarker.task'
    download(MODEL_URL, MODEL_SHA256, model)
    python = args.python or install(output, target)
    package = Path(subprocess.run(
        [str(python), '-c', 'import mediapipe, os; print(os.path.dirname(mediapipe.__file__))'],
        capture_output=True, text=True, check=True).stdout.strip())
    library = next((package / 'tasks/c').glob('libmediapipe.*'))
    library_digest = digest(library)
    image = PACKAGE / 'test/fixtures/landmark_tasks/pose.jpg'
    report = dict(target=target, platform=platform.platform(), pinned_version=version,
                  wheel_sha256=wheel_sha, library=library.name, library_sha256=library_digest,
                  library_matches_pin=library_digest == library_sha, arrangements={})
    for arrangement in ('python', 'header'):
        run = subprocess.run([str(python), '-B', __file__, '--output', str(output),
                              '--worker', str(model), str(image), arrangement],
                             capture_output=True, text=True, timeout=900)
        (output / f'{arrangement}.log').write_text(run.stdout + run.stderr, encoding='utf-8')
        if run.returncode:
            raise SystemExit(f'{arrangement} worker failed ({run.returncode}); see {arrangement}.log')
        result = json.loads(run.stdout.strip().splitlines()[-1])
        baseline = result['counts']['baseline']
        result['effects'] = {label: effect(result['counts'][label], baseline)
                             for label, _, _ in SETTINGS[1:]}
        result['acts_on_own_field'] = result['effects'] == OWN_FIELD
        report['arrangements'][arrangement] = result
    python_own = report['arrangements']['python']['acts_on_own_field']
    header_own = report['arrangements']['header']['acts_on_own_field']
    report['verdict'] = ('library reads the header order; the Python order is wrong'
                         if header_own and not python_own else
                         'library reads the Python order; the header order is wrong'
                         if python_own and not header_own else 'inconclusive')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    lines = [f"Holistic threshold order on {target}, mediapipe {report['arrangements']['python']['version']}",
             f"library {library.name} {library_digest} (matches pin: {report['library_matches_pin']})",
             f"Python struct order: {', '.join(report['arrangements']['python']['python_fields'][5:9])}", '',
             '| setting | value | own-field effect | Python order | header order |',
             '| --- | --- | --- | --- | --- |']
    for label, field, value in SETTINGS[1:]:
        lines.append(f"| {field} | {value} | {OWN_FIELD[label]} | "
                     f"{report['arrangements']['python']['effects'][label]} | "
                     f"{report['arrangements']['header']['effects'][label]} |")
    lines += ['', f"Baseline: {report['arrangements']['python']['counts']['baseline']}",
              f"Verdict: {report['verdict']}"]
    print('\n'.join(lines))
    (output / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    if not report['library_matches_pin']:
        raise SystemExit('The installed library does not match the pinned digest.')


if __name__ == '__main__':
    sys.exit(main())
