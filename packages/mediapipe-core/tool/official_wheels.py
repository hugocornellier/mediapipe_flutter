"""Google's official wheel pinned for this host, for the reference generators.

Linux and Windows come from core's `tasksWheelRuntimes`
(lib/src/native_assets/tasks_runtime.dart): the libraries core and the vision
package bundle. macOS is the wheel core's shared runtime was repackaged from.
Every digest is checked again where it is used.
"""
import platform
import re
from pathlib import Path

CORE = Path(__file__).resolve().parents[1]
MACOS = {
    'version': '1.0.1',
    'library': 'libmediapipe.dylib',
    'library_sha256': '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a',
    'wheel_url': ('https://files.pythonhosted.org/packages/18/56/'
                  '911762884caba685dc8156d0136c58196a228c2b447023cfa0cfdb32f6c5/'
                  'mediapipe-1.0.1-py3-none-macosx_11_0_arm64.whl'),
    'wheel_sha256': '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031',
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
