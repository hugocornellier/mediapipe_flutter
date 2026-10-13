"""What the maintainer tools share: a file's digest and a logged command."""
import hashlib
import platform
import shutil
import subprocess


def digest(path):
    """The SHA-256 of the file at `path`, in hex."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, log, env=None, timeout=3600, expect=0, tail=25):
    """Runs `command` in `cwd` with its output in `log`, prints the log's last
    `tail` lines and returns its text; fails unless the exit code is `expect`.

    On Windows, Dart and Flutter are batch entry points: a PATHEXT lookup can
    spell dart.EXE in upper case, after which Dart 3.12's hook runner appends
    another .exe, so both resolve to the .bat files Flutter's wrapper uses.
    """
    executable = str(command[0])
    if platform.system() == 'Windows' and executable in ('dart', 'flutter'):
        executable += '.bat'
    command = [shutil.which(executable) or executable, *map(str, command[1:])]
    print(' '.join(command), flush=True)
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    text = log.read_text(encoding='utf-8', errors='replace')
    print('\n'.join(text.splitlines()[-tail:]), flush=True)
    if result.returncode != expect:
        raise RuntimeError(f'Exit code {result.returncode}, expected {expect}: {log}')
    return text
