"""Checks the user-facing docs: Dart samples compile and relative links resolve.

Every ```dart block that has an `import` is a complete sample: each becomes a
library in a scratch Flutter app that depends on the four packages by path,
and `flutter analyze` must report nothing. Blocks without imports are
fragments and are skipped. Relative Markdown links must point at files that
exist in the repository.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
DOCS = [
    'README.md', 'MIGRATION.md', 'CONTRIBUTING.md',
    'doc/platform_setup.md', 'doc/privacy_and_licenses.md',
    'packages/mediapipe-core/README.md',
    'packages/mediapipe-task-vision/README.md',
    'packages/mediapipe-task-text/README.md',
    'packages/mediapipe-task-audio/README.md',
]
BLOCK = re.compile(r'^```dart\n(.*?)^```', re.S | re.M)
LINK = re.compile(r'\]\(([^)\s]+)\)')


def snippets(doc):
    text = (REPO / doc).read_text()
    for match in BLOCK.finditer(text):
        code = match.group(1)
        if re.search(r'^import ', code, re.M):
            yield text.count('\n', 0, match.start()) + 2, code


def broken_links(doc):
    text = (REPO / doc).read_text()
    for target in LINK.findall(text):
        if re.match(r'[a-z]+:', target) or target.startswith('#'):
            continue
        path = (REPO / doc).parent / target.split('#', 1)[0]
        if not path.exists():
            yield target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('docs', nargs='*', default=DOCS)
    args = parser.parse_args()
    failures = []
    for doc in args.docs:
        for target in broken_links(doc):
            failures.append(f'{doc}: broken link {target}')
    with tempfile.TemporaryDirectory(prefix='mediapipe-doc-') as tmp:
        app = Path(tmp) / 'doc_snippets'
        (app / 'lib').mkdir(parents=True)
        packages = REPO / 'packages'
        (app / 'pubspec.yaml').write_text(f"""name: doc_snippets
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_core:
    path: {packages / 'mediapipe-core'}
  mediapipe_vision:
    path: {packages / 'mediapipe-task-vision'}
  mediapipe_text:
    path: {packages / 'mediapipe-task-text'}
  mediapipe_audio:
    path: {packages / 'mediapipe-task-audio'}
""")
        (app / 'analysis_options.yaml').write_text(
            'analyzer:\n  errors:\n    avoid_print: ignore\n')
        origins = {}
        for doc in args.docs:
            for line, code in snippets(doc):
                name = f'snippet_{len(origins)}.dart'
                (app / 'lib' / name).write_text(code)
                origins[name] = f'{doc}:{line}'
        subprocess.run(['flutter', 'pub', 'get'], cwd=app, check=True,
                       capture_output=True)
        result = subprocess.run(['flutter', 'analyze', '--no-fatal-infos'],
                                cwd=app, capture_output=True, text=True)
        for line in (result.stdout + result.stderr).splitlines():
            found = re.search(r'lib/(snippet_\d+\.dart):(\d+)', line)
            if found and ('error' in line or 'warning' in line):
                failures.append(f'{origins[found.group(1)]} (+{found.group(2)}): '
                                f'{line.strip()}')
        print(f'{len(origins)} Dart samples compiled from {len(args.docs)} docs')
    for failure in failures:
        print(failure)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
