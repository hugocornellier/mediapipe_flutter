"""Copy a package the way a pub.dev consumer receives it, for fresh-app tests.

Only tracked files are copied, minus the top-level folders and files the
package's `.pubignore` keeps out of the published archive (tests, tools,
benchmarks, local builds and downloaded models), so this copy and the
published package cannot drift apart. Examples are left out too: an app never
receives them as code. The fresh consumer tests then fail the way an app
would if a declared asset, native source, hook or pin were missing.
"""
import shutil
import subprocess
from pathlib import Path


def _published_exclusions(source: Path):
    """Top-level names the package's `.pubignore` excludes (`/name/`)."""
    ignore = source / '.pubignore'
    lines = ignore.read_text().splitlines() if ignore.exists() else []
    return {line.strip('/') for line in lines
            if line.startswith('/') and line.count('/') <= 2}


def copy_package(source: Path, target: Path):
    """Copies [source]'s tracked files to [target] as pub.dev would ship them."""
    excluded = _published_exclusions(source) | {'build', 'models'}
    listed = subprocess.run(['git', 'ls-files', '-z', '--', '.'], cwd=source,
                            check=True, capture_output=True).stdout.decode()
    for relative in filter(None, listed.split('\0')):
        top = relative.split('/', 1)[0]
        if top in excluded or top.startswith('example'):
            continue
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, destination)
