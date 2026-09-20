#!/usr/bin/env python3
"""Archive reports, logs and artifact receipts, excluding signed apps/caches."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError(f'Refusing to overwrite {args.output}')
    files = {}
    for folder in ('campaign', 'validation', 'original-live'):
        for path in (args.workspace / folder).rglob('*'):
            if path.is_file() and path.suffix in ('.json', '.log') and '.app' not in str(path):
                files[str(path.relative_to(args.workspace))] = path
    for platform, folder in (('ios', args.workspace / 'recovered/apps/ios'),
                             ('macos', args.workspace / 'apps/macos')):
        for path in folder.glob('*/receipt.json'):
            files[f'artifacts/{platform}/{path.parent.name}/receipt.json'] = path
    for path in args.workspace.glob('*.json'):
        files[path.name] = path
    receipt = args.workspace / 'apps/ordinary-ios/receipt.json'
    if receipt.exists():
        files['artifacts/ordinary-ios/receipt.json'] = receipt
    checksums = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                 for name, path in sorted(files.items())}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, 'w:gz') as archive:
        for name, path in sorted(files.items()):
            archive.add(path, arcname=name)
    manifest = args.output.with_name(args.output.name + '.sha256.json')
    manifest.write_text(json.dumps({'archive_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
                                    'files': checksums}, indent=2) + '\n')
    print(f'Archived {len(files)} files to {args.output}')


if __name__ == '__main__':
    main()
