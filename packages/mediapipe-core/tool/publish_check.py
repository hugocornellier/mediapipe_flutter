"""Runs `flutter pub publish --dry-run` for each package, as pub.dev would see it.

Each package is copied outside the repository, as git tracks it (pub applies
the enclosing repository's .gitignore and the package's .pubignore). The
family packages depend on `mediapipe_core` by version, and their checked-in
`pubspec_overrides.yaml` resolves it against the sibling copy, as a checkout
does; pub leaves that file out of the archive. Nothing is published: this
tool never runs `pub publish` without `--dry-run`.

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
sys.path.insert(0, str(CORE / 'tool'))
from families import PACKAGES, package_folders  # noqa: E402

FAMILY = package_folders()


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
            # The only expected hint: a family's mediapipe_core resolves
            # through its pubspec_overrides.yaml, as in a checkout.
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
