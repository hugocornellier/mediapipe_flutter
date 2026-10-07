"""The families' pinned models, read from each family's `lib/models.dart`.

Maintainer scripts check every model they run against the package's own pin,
so a pin lives in one place. The mirror inventory reads the same table.
"""
from pathlib import Path
import re
from urllib.parse import urlsplit

PACKAGES = Path(__file__).resolve().parents[2]
SOURCES = [
    'mediapipe-task-text/lib/models.dart',
    'mediapipe-task-vision/lib/models.dart',
    'mediapipe-task-audio/lib/models.dart',
]
_STRINGS = re.compile(r"'([^']*)'")


def _literals(expression):
    return ''.join(_STRINGS.findall(expression))


def model_pins():
    """Every pinned model: `{url, sha256, source}`, `source` being the
    registry relative to `packages/`."""
    pins = []
    for relative in SOURCES:
        text = (PACKAGES / relative).read_text()
        if 'text/' in relative:
            for match in re.finditer(r'DownloadAsset\((.*?)\)', text, re.S):
                fields = re.search(r'url:\s*(.*?),\s*sha256:\s*(.*?),?\s*$',
                                   match.group(1), re.S)
                if fields:
                    pins.append({'url': _literals(fields.group(1)),
                                 'sha256': _literals(fields.group(2)),
                                 'source': relative})
        else:
            for match in re.finditer(r'const (\w+)Url\s*=\s*(.*?);', text, re.S):
                stem = match.group(1)
                digest = re.search(r'const ' + stem + r'Sha256\s*=\s*(.*?);', text, re.S)
                if digest:
                    pins.append({'url': _literals(match.group(2)),
                                 'sha256': _literals(digest.group(1)),
                                 'source': relative})
    return pins


def model_sha256(filename):
    """The pinned SHA-256 of the model Google publishes as [filename]."""
    digests = {pin['sha256'] for pin in model_pins()
               if urlsplit(pin['url']).path.rsplit('/', 1)[-1] == filename}
    if len(digests) != 1:
        raise KeyError(f'{filename} has {len(digests)} pins')
    return digests.pop()
