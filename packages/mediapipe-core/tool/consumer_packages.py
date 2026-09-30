"""Copy a package the way a pub.dev consumer receives it, for fresh-app tests.

Only tracked files are copied, and never the maintainer-only folders: tests,
tools, examples, local builds and downloaded models. The fresh
consumer tests check those stay absent, so no test can reach a source build.
Everything a package declares (assets, Android and iOS sources, hooks, pins)
comes along, so a test fails the way an app would if one were missing.
"""
import shutil
import subprocess
from pathlib import Path

MAINTAINER_ONLY = {'build', 'models', 'test', 'tool'}


def copy_package(source: Path, target: Path):
    """Copies [source]'s tracked files to [target], minus maintainer folders."""
    listed = subprocess.run(['git', 'ls-files', '-z', '--', '.'], cwd=source,
                            check=True, capture_output=True).stdout.decode()
    for relative in filter(None, listed.split('\0')):
        top = relative.split('/', 1)[0]
        if top in MAINTAINER_ONLY or top.startswith('example'):
            continue
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, destination)
