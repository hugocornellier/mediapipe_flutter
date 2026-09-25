"""Test the text and audio packages against Google's library on this host.

Installs Google's pinned official wheel for this host once, generates the text
and audio references with it, downloads the pinned models, and runs both
packages' Dart suites against those same-host references. CI runs it on the
Linux x64 and Windows x64 desktop runners; it runs on macOS arm64 as well.
Python only prepares the expected outputs; the suites load Google's library
through the packages, as an app does.
"""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
TEXT = REPO / 'packages/mediapipe-task-text'
AUDIO = REPO / 'packages/mediapipe-task-audio'
sys.path.insert(0, str(REPO / 'packages/mediapipe-core/tool'))
from official_wheels import host_runtime, venv_python  # noqa: E402


def run(command, cwd, log, env=None, timeout=1800):
    executable = str(command[0])
    if platform.system() == 'Windows' and executable == 'dart':
        # As in the vision package's test_desktop.py: Dart's hook runner needs
        # the batch entry point Flutter's wrapper uses.
        executable = 'dart.bat'
    command = [shutil.which(executable) or executable, *map(str, command[1:])]
    print(' '.join(command), flush=True)
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    print('\n'.join(log.read_text(encoding='utf-8', errors='replace').splitlines()[-25:]),
          flush=True)
    result.check_returncode()


def main():
    # Test names and Google's logs are UTF-8; Windows CI defaults to cp1252.
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    runtime = host_runtime()
    evidence = REPO / 'build/codex-tmp/text-audio'
    evidence.mkdir(parents=True, exist_ok=True)
    environment = REPO / f'build/codex-tmp/official-python-{runtime["version"]}'
    python = venv_python(environment)
    if not python.exists():
        run([sys.executable, '-m', 'venv', environment], REPO, evidence / 'venv.log')
    run([python, '-m', 'pip', 'install', '--disable-pip-version-check',
         runtime['wheel_url'] + '#sha256=' + runtime['wheel_sha256']], REPO, evidence / 'pip.log')

    for package in (TEXT, AUDIO):
        run(['dart', 'pub', 'get'], package, evidence / f'{package.name}-pub.log')
    run(['dart', 'tool/download_classic_text.dart'], TEXT, evidence / 'text-models.log')
    run(['dart', 'run', 'tool/download_model.dart'], AUDIO, evidence / 'audio-model.log')
    text_reference = REPO / 'build/classic-text-reference'
    audio_reference = REPO / 'build/audio-reference'
    run([sys.executable, '-B', TEXT / 'tool/prepare_classic_text_reference.py',
         '--python', python, '--output-dir', text_reference], REPO,
        evidence / 'text-reference.log')
    run([sys.executable, '-B', AUDIO / 'tool/prepare_audio_reference.py',
         '--python', python, '--output-dir', audio_reference], REPO,
        evidence / 'audio-reference.log')

    env = {**os.environ,
           'MEDIAPIPE_CLASSIC_TEXT_REFERENCE_DIR': str(text_reference),
           'MEDIAPIPE_AUDIO_REFERENCE_DIR': str(audio_reference)}
    run(['dart', 'test', '--reporter', 'expanded'], TEXT, evidence / 'text-tests.log', env)
    run(['dart', 'test', '--reporter', 'expanded'], AUDIO, evidence / 'audio-tests.log', env)
    receipts = {name: json.loads((folder / 'provenance.json').read_text(encoding='utf-8'))
                for name, folder in [('text', text_reference), ('audio', audio_reference)]}
    (evidence / 'report.json').write_text(json.dumps({
        'runtime': 'mediapipe==' + runtime['version'],
        'library_sha256': runtime['library_sha256'],
        'os': platform.platform(),
        'tasks': ['audio_classifier', 'language_detector', 'text_classifier', 'text_embedder'],
        'checked_in_reference_differences': {
            name: receipt['checked_in_reference_differences']
            for name, receipt in receipts.items()},
    }, indent=2) + '\n', encoding='utf-8')
    print(f'Text and audio passed against Google\'s {runtime["version"]} library: {evidence}',
          flush=True)


if __name__ == '__main__':
    main()
