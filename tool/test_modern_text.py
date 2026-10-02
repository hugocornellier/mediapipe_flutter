"""Test EmbeddingGemma, Proofreader and Summarizer against Google's library here.

Installs Google's pinned official wheel for this host once (the same environment
tool/test_text_audio.py uses), downloads the three pinned models, generates the
three references with that wheel, and runs the text package's example_embedding
suite against them: Google's completed and streamed outputs for the same model,
runtime and inputs, each option, stream lifecycle, errors and disposal. CI runs
it on the Linux x64 and Windows x64 desktop runners; it runs on macOS arm64 as
well. Python only prepares the expected outputs; the suite loads Google's
library through the package, as an app does.
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
EXAMPLE = TEXT / 'example_embedding'
sys.path.insert(0, str(REPO / 'packages/mediapipe-core/tool'))
from official_wheels import host_runtime, venv_python  # noqa: E402

TASKS = ['embedding_gemma', 'text_proofreader', 'text_summarizer']


def run(command, cwd, log, env=None, timeout=3600):
    executable = str(command[0])
    if platform.system() == 'Windows' and executable in ('dart', 'flutter'):
        # As in the vision package's test_desktop.py: Dart's hook runner needs
        # the batch entry point Flutter's wrapper uses.
        executable += '.bat'
    command = [shutil.which(executable) or executable, *map(str, command[1:])]
    print(' '.join(command), flush=True)
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    print('\n'.join(log.read_text(encoding='utf-8', errors='replace').splitlines()[-25:]),
          flush=True)
    result.check_returncode()


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    runtime = host_runtime()
    evidence = REPO / 'build/codex-tmp/modern-text'
    evidence.mkdir(parents=True, exist_ok=True)
    environment = REPO / f'build/codex-tmp/official-python-{runtime["version"]}'
    python = venv_python(environment)
    if not python.exists():
        run([sys.executable, '-m', 'venv', environment], REPO, evidence / 'venv.log')
    run([python, '-m', 'pip', 'install', '--disable-pip-version-check',
         runtime['wheel_url'] + '#sha256=' + runtime['wheel_sha256']], REPO, evidence / 'pip.log')

    run(['dart', 'pub', 'get'], TEXT, evidence / 'text-pub.log')
    for tool in ('download_embedding_gemma', 'download_proofreader', 'download_summarizer'):
        run(['dart', f'tool/{tool}.dart'], TEXT, evidence / f'{tool}.log')
    reference = REPO / 'build/modern-text-reference'
    run([sys.executable, '-B', TEXT / 'tool/prepare_modern_text_reference.py',
         '--python', python, '--output-dir', reference], REPO, evidence / 'reference.log')

    if platform.system() != 'Windows':
        # The callback-copy bridge, under AddressSanitizer, as make
        # test_text_stream_bridge runs it on macOS; MSVC compiles it on Windows
        # inside the package's build hook, which the suite below exercises.
        binary = evidence / 'text_stream_bridge_test'
        run(['clang', '-Wall', '-Wextra', '-Werror', '-g', '-fsanitize=address', '-pthread',
             TEXT / 'native/text_stream_bridge.c', TEXT / 'native/text_stream_bridge_test.c',
             '-o', binary], REPO, evidence / 'bridge-build.log')
        run([binary], REPO, evidence / 'bridge-test.log')

    env = {**os.environ, 'MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR': str(reference)}
    run(['flutter', 'pub', 'get'], EXAMPLE, evidence / 'example-pub.log')
    run(['dart', 'test', '--reporter', 'expanded'], EXAMPLE, evidence / 'example-tests.log', env)
    receipt = json.loads((reference / 'provenance.json').read_text(encoding='utf-8'))
    (evidence / 'report.json').write_text(json.dumps({
        'runtime': 'mediapipe==' + runtime['version'],
        'library_sha256': runtime['library_sha256'],
        'os': platform.platform(),
        'tasks': TASKS,
        'references': receipt['references'],
    }, indent=2) + '\n', encoding='utf-8')
    print(f'Modern text tasks passed against Google\'s {runtime["version"]} library: {evidence}',
          flush=True)


if __name__ == '__main__':
    main()
