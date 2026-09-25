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
INTEGRITY = '03cqJx+BZ+WpmuDqq+4Z8Bn7BdJyEPxU7Q1iuczjrh3YGiaAD2VMYf5JCLd+vQy7nNrlOOvUQlTnX0nYRpAUOA=='
FILES = ['text_bundle.mjs', 'text_bundle.js',
         'wasm/text_wasm_internal.js', 'wasm/text_wasm_internal.wasm',
         'wasm/text_wasm_nosimd_internal.js', 'wasm/text_wasm_nosimd_internal.wasm',
         'wasm/text_wasm_module_internal.js', 'wasm/text_wasm_module_internal.wasm']


def main():
    url = f'https://registry.npmjs.org/@mediapipe/tasks-text/-/tasks-text-{VERSION}.tgz'
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
        'package': '@mediapipe/tasks-text', 'version': VERSION,
        'url': url, 'npm_integrity': f'sha512-{INTEGRITY}',
        'files_sha256': hashes,
    }, indent=2) + '\n')
    print(f'Prepared verified official MediaPipe text web runtime {VERSION}')


if __name__ == '__main__':
    main()
