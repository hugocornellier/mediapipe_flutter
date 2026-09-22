"""Validate CPU task references in a fresh Flutter iOS simulator consumer.

The default covers the two validated face tasks. --experimental-all-tasks
enables the other source-built tasks only in an isolated package copy, to
measure compatibility without changing the package's support declarations.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import struct
import subprocess
import tempfile
import threading
import time

from build_native import PACKAGE, REPO
from test_desktop import digest, run
from macho_metadata import inspect
from mobile_consumer import prepare_app, reference_deltas

# A passing run prints its first test line within seconds of the Xcode build.
LAUNCH_TIMEOUT = 300
ATTEMPT_TIMEOUT = 1200


def _pump(stream, lines):
    for line in stream:
        lines.put(line)
    lines.put(None)


def _stop(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    except ProcessLookupError:
        pass


def run_integration(command, udid, app, root, report, attempts=2):
    """Runs the integration suite, retrying once when the app never connects.

    On hosted runners `flutter test` sometimes goes silent after "Xcode build
    done" and before the first test until the job times out: 5 of 13 runs on
    2026-09-21 and 22, all on one runner image. Each stall keeps its output and
    the simulator's app log, then the simulator is rebooted for the retry. A
    test failure is not retried.
    """
    for attempt in range(1, attempts + 1):
        log = root / 'integration.log'
        print(' '.join(map(str, command)), flush=True)
        process = subprocess.Popen(command, cwd=app, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True,
                                   errors='replace', start_new_session=True)
        lines = queue.Queue()
        threading.Thread(target=_pump, args=(process.stdout, lines), daemon=True).start()
        deadline = time.monotonic() + ATTEMPT_TIMEOUT
        built = None
        connected = stalled = False
        with log.open('w', encoding='utf-8') as output:
            while True:
                limit = built + LAUNCH_TIMEOUT if built is not None else deadline
                try:
                    line = lines.get(timeout=max(limit - time.monotonic(), 0))
                except queue.Empty:
                    stalled = True
                    break
                if line is None:
                    break
                output.write(line)
                output.flush()
                print(line, end='', flush=True)
                if built is not None:
                    connected, built = True, None
                elif not connected and 'Xcode build done' in line:
                    built = time.monotonic()
        if not stalled:
            returncode = process.wait()
            if returncode:
                raise subprocess.CalledProcessError(returncode, command)
            report['integration_attempts'] = attempt
            return
        _stop(process)
        log.rename(root / f'integration-stall-{attempt}.log')
        with (root / f'simulator-stall-{attempt}.log').open('w', encoding='utf-8') as output:
            try:
                subprocess.run(['xcrun', 'simctl', 'spawn', udid, 'log', 'show', '--last', '15m',
                                '--style', 'compact', '--predicate', 'process == "Runner"'],
                               stdout=output, stderr=subprocess.STDOUT, timeout=180)
            except subprocess.TimeoutExpired:
                output.write('log show timed out\n')
        report.setdefault('integration_stalls', []).append(
            'after the Xcode build' if built is not None else 'attempt timeout')
        print(f'flutter test stalled (attempt {attempt}); rebooting the simulator', flush=True)
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid])
        subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True, timeout=180)
    raise RuntimeError(f'flutter test stalled in all {attempts} attempts; '
                       'see integration-stall-*.log and simulator-stall-*.log')


def arm64_slice(data):
    # Flutter may wrap even a single architecture in a universal container.
    if struct.unpack_from('>I', data)[0] == 0xcafebabe:
        count = struct.unpack_from('>I', data, 4)[0]
        cpu, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8)
        if count != 1 or cpu != 0x0100000c or offset + size > len(data):
            raise ValueError('Expected exactly one valid arm64 Mach-O slice')
        return data[offset:offset + size]
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Installed iOS simulator UUID')
    parser.add_argument('--experimental-all-tasks', action='store_true')
    parser.add_argument('--prebuilt', action='store_true')
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
    candidates = [(runtime, device) for runtime, entries in devices.items()
                  if '.iOS-' in runtime for device in entries
                  if (device['udid'] == args.device if args.device
                      else device['state'] == 'Booted')]
    if not candidates:
        raise SystemExit('Boot an iOS simulator or specify --device UUID.')
    runtime, device = candidates[0]
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'],
                   check=True, timeout=180)
    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='ios-consumer-', dir=build))
    print(f'Validation artifacts: {root}', flush=True)
    selected = ['face_detector', 'face_landmarker']
    suites = ['face_detector', 'face_landmarker', 'pixel_conversion']
    if args.experimental_all_tasks:
        selected += ['object_detector', 'image_classifier', 'image_embedder',
                     'hand_landmarker', 'gesture_recognizer', 'pose_landmarker',
                     'holistic_landmarker', 'image_segmenter', 'interactive_segmenter_legacy']
        suites += ['object_detector', 'image_tasks', 'landmark_tasks', 'segmenter_tasks']
    report = {'target': 'ios-simulator/arm64', 'delegate': 'CPU',
              'device': device['udid'], 'runtime': runtime, 'tasks': selected,
              'experimental_support_override': args.experimental_all_tasks,
              'prebuilt': args.prebuilt, 'status': 'running'}
    report_path = root / 'report.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    try:
        models = ['blaze_face_short_range.tflite', 'face_landmarker.task']
        if args.experimental_all_tasks:
            models += ['efficientdet_lite0.tflite', 'efficientnet_lite0.tflite',
                       'mobilenet_v3_small.tflite', 'hand_landmarker.task',
                       'gesture_recognizer.task', 'pose_landmarker_lite.task',
                       'holistic_landmarker.task', 'deeplab_v3.tflite', 'magic_touch.tflite']
        app, vision = prepare_app(root, 'ios', selected, suites, models, prebuilt=args.prebuilt)
        project = app / 'ios/Runner.xcodeproj/project.pbxproj'
        project.write_text(project.read_text().replace(
            'IPHONEOS_DEPLOYMENT_TARGET = 13.0;', 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;').replace(
            'buildSettings = {', 'buildSettings = {\n\t\t\t\t"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64;'))
        if not args.prebuilt:
            source = PACKAGE / 'build/native/ios-simulator/arm64'
            library = source / 'libmediapipe.dylib'
            if not library.exists():
                raise RuntimeError('Run tool/build_ios_simulator.py first.')
            report['library_sha256'] = digest(library)
            report['library_manifest'] = json.loads((source / 'manifest.json').read_text())
            shutil.copytree(source, vision / 'build/native/ios-simulator/arm64')
        if args.experimental_all_tasks:
            capabilities = vision / 'lib/capabilities.dart'
            content = capabilities.read_text().replace(
                "VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null}",
                "VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null, 'ios/arm64': null}")
            capabilities.write_text(content)
            releases = vision / 'sdk_downloads.dart'
            content = releases.read_text()
            content = re.sub(
                r"(target: 'ios-simulator/arm64',.*?tasks:) \{[^}]+\}",
                lambda match: match.group(1) + ' {' + ', '.join(
                    repr(task) for task in selected) + '}', content, flags=re.S)
            releases.write_text(content)
        run(['flutter', 'pub', 'get'], app, root / 'pub.log')
        run_integration([shutil.which('flutter') or 'flutter', 'test', '-d', device['udid'],
                         'integration_test/tasks_test.dart', '--reporter', 'expanded'],
                        device['udid'], app, root, report)
        integration = (root / 'integration.log').read_text()
        report['reference_deltas'] = reference_deltas(
            integration, ['face_detector', 'face_landmarker'])
        totals = re.findall(r'\+(\d+)(?: ~(\d+))?: All tests passed!',
                            (root / 'integration.log').read_text())
        if not totals:
            raise RuntimeError('Integration runner did not report passing test counts')
        passed, skipped = totals[-1]
        report['tests'] = {'passed': int(passed), 'skipped': int(skipped or 0)}
        run(['flutter', 'build', 'ios', '--simulator', '--debug'],
            app, root / 'build-debug.log')
        bundle = app / 'build/ios/iphonesimulator/Runner.app'
        library = vision / 'build/native/ios-simulator/arm64/libmediapipe.dylib'
        if args.prebuilt:
            row = re.search(r"target: 'ios-simulator/arm64',(.*?)\n  \),",
                            (vision / 'sdk_downloads.dart').read_text(), re.S)
            if row is None:
                raise RuntimeError('No pinned simulator release')
            expected = re.search(r"librarySha256:\s*'([a-f0-9]{64})'", row.group(1)).group(1)
            candidates = [p for p in (app / '.dart_tool').rglob('libmediapipe.dylib')
                          if digest(p) == expected]
            if not candidates:
                raise RuntimeError('Public consumer did not extract the pinned simulator runtime')
            library = candidates[0]
            report['library_sha256'] = expected
        if library.exists():
            original = library.read_bytes()
            before = inspect(original)
            libraries = {}
            for stem in ['face_detector', 'face_landmarker']:
                path = bundle / f'Frameworks/{stem}.framework/{stem}'
                modified = arm64_slice(path.read_bytes())
                after = inspect(modified)
                if (before[4] != after[4] or
                        original[before[0]:before[1]] != modified[after[0]:after[1]]):
                    raise RuntimeError(f'Bundling changed native code/data: {path}')
                libraries[stem] = {'source_sha256': digest(library),
                                   'bundled_sha256': digest(path),
                                   'code_and_data_unchanged': True}
            report['bundled_libraries'] = libraries
        run(['xcrun', 'simctl', 'install', device['udid'], bundle],
            app, root / 'install.log')
        identifier = subprocess.check_output(
            ['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier',
             str(bundle / 'Info.plist')], text=True).strip()
        run(['xcrun', 'simctl', 'launch', '--console', device['udid'], identifier],
            app, root / 'inference-debug.log', timeout=180)
        if 'bundled cpu Face Detector and Face Landmarker inference passed.' not in (
                root / 'inference-debug.log').read_text():
            raise RuntimeError('Packaged app did not confirm face inference')
        report['debug_app_inference'] = 'passed'
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Report: {report_path}', flush=True)


if __name__ == '__main__':
    main()
