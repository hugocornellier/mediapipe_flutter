"""Runs `flutter pub publish --dry-run` for each package, as pub.dev would see it.

Each package is copied outside the repository (pub applies the enclosing
repository's .gitignore), without `publish_to: none`, and with its path
dependencies on sibling packages turned into the version constraints a
published package carries. A `pubspec_overrides.yaml` resolves those against
the sibling copies, since they are not on pub.dev yet. Nothing is published:
this tool never runs `pub publish` without `--dry-run`.

Exit status is non-zero unless every package validates with zero warnings.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

CORE = Path(__file__).resolve().parents[1]
PACKAGES = CORE.parent
FAMILY = ['mediapipe-core', 'mediapipe-task-vision', 'mediapipe-task-text',
          'mediapipe-task-audio']
PATH_DEPENDENCY = re.compile(
    r'^  (mediapipe_[a-z]+):\n    path: \.\./(mediapipe-[a-z-]+)\n', re.M)


def version(package):
    text = (PACKAGES / package / 'pubspec.yaml').read_text()
    return re.search(r'^version: (\S+)$', text, re.M).group(1)


def copy(package, target):
    """Copies the files git would keep (tracked or new, not ignored)."""
    listed = subprocess.run(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        cwd=PACKAGES / package, check=True, capture_output=True).stdout.decode()
    for relative in filter(None, listed.split('\0')):
        source = PACKAGES / package / relative
        if source.is_file() and not source.is_symlink():
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)


def prepare(package, root):
    target = root / package
    copy(package, target)
    pubspec = target / 'pubspec.yaml'
    text = re.sub(r'(?:^#.*\n)*^publish_to: none\n', '', pubspec.read_text(),
                  flags=re.M)
    overrides = []

    def constraint(match):
        name, directory = match.groups()
        overrides.append(f'  {name}:\n    path: ../{directory}\n')
        return f'  {name}: ^{version(directory)}\n'

    text = PATH_DEPENDENCY.sub(constraint, text)
    pubspec.write_text(text)
    if overrides:
        (target / 'pubspec_overrides.yaml').write_text(
            'dependency_overrides:\n' + ''.join(overrides))
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', nargs='*', default=FAMILY,
                        help='Package directories under packages/')
    args = parser.parse_args()
    failed = []
    with tempfile.TemporaryDirectory(prefix='mediapipe-publish-') as tmp:
        root = Path(tmp)
        for package in FAMILY:
            prepare(package, root)
        for package in args.packages:
            result = subprocess.run(
                ['flutter', 'pub', 'publish', '--dry-run'], cwd=root / package,
                capture_output=True, text=True)
            output = result.stdout + result.stderr
            size = re.search(r'Total compressed archive size: (.+)\.', output)
            # The only expected hint: siblings resolve through the override
            # until mediapipe_core itself is on pub.dev.
            clean = re.search(r'Package has 0 warnings(\.| and)', output) is not None
            print(f'{package}: {"ok" if clean else "FAILED"}, '
                  f'archive {size.group(1) if size else "unknown"}', flush=True)
            if not clean:
                failed.append(package)
                report = output[output.find('Validating package'):]
                print(report or output, flush=True)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
