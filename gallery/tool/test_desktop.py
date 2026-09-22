"""Build and exercise the actual CPU gallery on a Windows/Linux host."""
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import sys

GALLERY = Path(__file__).resolve().parents[1]
REPO = GALLERY.parent


def main():
    # Flutter emits Unicode build markers; Windows CI defaults to cp1252.
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    target = {'Linux': 'linux', 'Windows': 'windows'}.get(platform.system())
    if target is None or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise SystemExit('Run this validation on Windows x64 or Linux x64.')
    evidence = REPO / f'build/codex-tmp/gallery-desktop-{target}'
    evidence.mkdir(parents=True, exist_ok=True)

    def run(args, name, timeout=1200):
        executable = shutil.which(str(args[0]))
        if executable is None:
            raise RuntimeError(f'Missing command: {args[0]}')
        print(f'{name}: {args}', flush=True)
        with (evidence / f'{name}.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([executable, *map(str, args[1:])],
                                    cwd=GALLERY, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            print((evidence / f'{name}.log').read_text(encoding='utf-8', errors='replace'),
                  flush=True)
            raise RuntimeError(f'{name} failed ({result.returncode})')

    run([sys.executable, '-B', GALLERY / 'tool/prepare.py',
         '--target', f'{target}/x64'], 'prepare')
    manifest = json.loads((GALLERY / 'assets/manifest.json').read_text())
    required = {'face_landmarker', 'hand_landmarker', 'pose_landmarker'}
    if not required <= set(manifest['tasks']):
        raise RuntimeError('Download the face, hand and pose models first.')
    run(['flutter', 'pub', 'get'], 'pub')
    run(['flutter', 'analyze', 'lib', 'test',
         'integration_test/desktop_cpu_camera_test.dart',
         'integration_test/runtime_test.dart'], 'analyze')
    run(['flutter', 'test', 'test'], 'unit')
    for name in ['assets_test', 'runtime_test', 'desktop_cpu_camera_test']:
        run(['flutter', 'test', '-d', target,
             f'integration_test/{name}.dart', '--reporter', 'expanded'], name)
    run(['flutter', 'build', target, '--release'], 'release')
    bundle = GALLERY / ('build/linux/x64/release/bundle' if target == 'linux'
                         else 'build/windows/x64/runner/Release')
    runtime_name = 'libmediapipe.so' if target == 'linux' else 'libmediapipe.dll'
    libraries = list(bundle.rglob(runtime_name))
    if len(libraries) != 1:
        raise RuntimeError(f'Expected one official runtime, got {libraries}')
    library = libraries[0]
    sha = hashlib.sha256(library.read_bytes()).hexdigest()
    (evidence / 'report.json').write_text(json.dumps({
        'target': f'{target}/x64', 'delegates': ['cpu'],
        'runtime': str(library.relative_to(bundle)), 'runtime_sha256': sha,
        'checks': ['native-camera-registration-and-enumeration',
                   'assets', 'cross-task-runtime-coexistence',
                   'gallery-supplied-camera-rgba-bgra-switch-restart-cleanup',
                   'release-build'],
        'physical_webcam_tested': False,
    }, indent=2) + '\n')
    print(f'CPU gallery validation passed: {evidence}', flush=True)


if __name__ == '__main__':
    main()
