"""Google's official wheel pinned for this host, for the reference generators.

Linux and Windows come from core's `tasksWheelRuntimes`
(lib/src/native_assets/tasks_runtime.dart): the libraries core bundles for
every family. macOS is the wheel core's engine was repackaged from (its
`tasksRuntimeReleases` row). Every digest is checked again where it is used.
"""
import platform
import re
from pathlib import Path

CORE = Path(__file__).resolve().parents[1]
MACOS = {
    'version': '1.0.0',
    'library': 'libmediapipe.dylib',
    'library_sha256': 'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
    'wheel_url': ('https://files.pythonhosted.org/packages/42/d7/'
                  '3a5dfaa86128db110c62a4d0f0c948304817932c9dd3257313bbdf24f7d5/'
                  'mediapipe-1.0.0-py3-none-macosx_11_0_arm64.whl'),
    'wheel_sha256': '7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82',
}


def _strings(source):
    return ''.join(re.findall(r"'([^']*)'", source))


def desktop_runtime(target):
    """The row core's build hook bundles for `linux/x64` or `windows/x64`."""
    source = (CORE / 'lib/src/native_assets/tasks_runtime.dart').read_text(encoding='utf-8')
    row = re.search(r"'" + re.escape(target) + r"': OfficialWheelLibrary\((.*?)\n  \),",
                    source, re.S).group(1)
    return {
        'version': re.search(r"version: '([0-9.]+)'", row).group(1),
        'library': re.search(r"libraryName: '([^']+)'", row).group(1),
        'library_sha256': _strings(re.search(r'librarySha256:(.*?),', row, re.S).group(1)),
        'wheel_url': _strings(re.search(r'url:(.*?),', row, re.S).group(1)),
        'wheel_sha256': _strings(re.search(r'sha256:(.*?),', row, re.S).group(1)),
    }


def macos_engine():
    """Core's pinned macOS engine archive (`tasksRuntimeReleases`), as bundled."""
    source = (CORE / 'lib/src/native_assets/tasks_runtime.dart').read_text(encoding='utf-8')
    row = re.search(r"'macos/arm64': TasksRuntimeRelease\((.*?)\n  \),", source, re.S).group(1)
    url = _strings(re.search(r'url:(.*?),', row, re.S).group(1))
    library = re.search(r"libraryName: '([^']+)'", row).group(1)
    return {
        'release': re.search(r"release: '([^']+)'", row).group(1),
        'version': re.search(r"version: '([0-9.]+)'", row).group(1),
        'archive_url': url,
        'archive_name': url.rsplit('/', 1)[-1],
        'archive_sha256': _strings(re.search(r'sha256:(.*?),', row, re.S).group(1)),
        'library': library,
        'library_sha256': _strings(re.search(r'librarySha256:(.*?),', row, re.S).group(1)),
        # Flutter names a bundled framework after its file, without `lib`.
        'framework': library.removeprefix('lib').split('.')[0] + '.framework',
    }


def host_runtime():
    """The pinned official runtime for this host, or SystemExit where none is."""
    host = (platform.system(), platform.machine())
    if host == ('Darwin', 'arm64'):
        return dict(MACOS)
    target = {('Linux', 'x86_64'): 'linux/x64', ('Windows', 'AMD64'): 'windows/x64'}.get(host)
    if target is None:
        raise SystemExit(f'No official wheel is pinned for {host[0]} {host[1]}.')
    return desktop_runtime(target)


def venv_python(environment):
    """The interpreter inside a virtual environment created on this host."""
    return environment / ('Scripts/python.exe' if platform.system() == 'Windows' else 'bin/python')
