"""Download and verify the pinned official Google JS/WASM distribution."""
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
VERSION = '1.0.1'
INTEGRITY = 'znfNNj9p6sAfsmrK+mjpW5H2NdWEcyvebjIcxjM3onv5God5S//fT4wFZ76quYL9J9SSTi2EkdUCq2zjYbzK2w=='
FILES = ['audio_bundle.mjs', 'audio_bundle.js',
         'wasm/audio_wasm_internal.js', 'wasm/audio_wasm_internal.wasm',
         'wasm/audio_wasm_nosimd_internal.js', 'wasm/audio_wasm_nosimd_internal.wasm',
         'wasm/audio_wasm_module_internal.js', 'wasm/audio_wasm_module_internal.wasm']


def main():
    url = f'https://registry.npmjs.org/@mediapipe/tasks-audio/-/tasks-audio-{VERSION}.tgz'
    data = urllib.request.urlopen(url, timeout=120).read()
    if base64.b64encode(hashlib.sha512(data).digest()).decode() != INTEGRITY:
        raise RuntimeError('Official runtime integrity mismatch')
    output = PACKAGE / 'assets/runtime'
    hashes = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for name in FILES:
            content = archive.extractfile(f'package/{name}').read()
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            hashes[name] = hashlib.sha256(content).hexdigest()
    (output / 'provenance.json').write_text(json.dumps({
        'package': '@mediapipe/tasks-audio', 'version': VERSION,
        'url': url, 'npm_integrity': f'sha512-{INTEGRITY}',
        'files_sha256': hashes,
    }, indent=2) + '\n')
    print(f'Prepared verified official MediaPipe audio web runtime {VERSION}')


if __name__ == '__main__':
    main()
