#!/usr/bin/env python3
"""Inventory reviewed pins, or fill a SHA-named offline source directory."""

import argparse
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[3]
PACKAGES = ROOT / 'packages'
RUNTIME_SOURCES = {
    'mediapipe-core/lib/src/native_assets/tasks_runtime.dart': None,
    'mediapipe-core/lib/src/native_assets/ios_sdk.dart': ['ios/arm64', 'ios-simulator/arm64'],
    'mediapipe-task-vision/sdk_downloads.dart': None,
}
MODEL_SOURCES = [
    'mediapipe-task-text/lib/models.dart',
    'mediapipe-task-vision/lib/models.dart',
    'mediapipe-task-audio/lib/models.dart',
]
STRINGS = re.compile(r"'([^']*)'")
PIN = re.compile(r'DownloadAsset\((.*?)\)', re.S)
HEX = re.compile(r'^[0-9a-f]{64}$')


def literals(expression):
    return ''.join(STRINGS.findall(expression))


GEMMA_MODELS = {
    'embedding_gemma.task',
    'proofread_quant_200m.litertlm',
    'summarization_quant_200m_2modes.litertlm',
}


def add(items, kind, target, url, digest, label):
    if not url.startswith('https://') or not HEX.fullmatch(digest):
        raise ValueError(f'Unparseable {kind} pin: {label}')
    name = urlsplit(url).path.rsplit('/', 1)[-1]
    key = (kind, digest)
    item = items.setdefault(key, {
        'kind': kind, 'sha256': digest, 'urls': [], 'targets': [],
        'release_asset': f'{digest}-{name}', 'license': 'UNKNOWN',
        'pin': label,
    })
    if url not in item['urls']:
        item['urls'].append(url)
    for one in target:
        if one not in item['targets']:
            item['targets'].append(one)


def runtime_assets(items):
    for relative, fixed in RUNTIME_SOURCES.items():
        source = PACKAGES / relative
        text = source.read_text()
        for match in PIN.finditer(text):
            block = match.group(1)
            fields = re.search(r'url:\s*(.*?),\s*sha256:\s*(.*?),?\s*$', block, re.S)
            if not fields:
                continue
            url, digest = literals(fields.group(1)), literals(fields.group(2))
            if fixed:
                targets = fixed
            else:
                preceding = text[:match.start()]
                targets = [re.findall(r"target: '([^']+)'", preceding)[-1]]
            add(items, 'runtime', targets, url, digest, relative)


def model_assets(items):
    for relative in MODEL_SOURCES:
        text = (PACKAGES / relative).read_text()
        if 'text/' in relative:
            for match in PIN.finditer(text):
                block = match.group(1)
                fields = re.search(r'url:\s*(.*?),\s*sha256:\s*(.*?),?\s*$', block, re.S)
                if fields:
                    add(items, 'model', ['all'], literals(fields.group(1)),
                        literals(fields.group(2)), relative)
        else:
            for match in re.finditer(r'const (\w+)Url\s*=\s*(.*?);', text, re.S):
                stem = match.group(1)
                digest = re.search(r'const ' + stem + r'Sha256\s*=\s*(.*?);', text, re.S)
                if digest:
                    add(items, 'model', ['all'], literals(match.group(2)),
                        literals(digest.group(1)), relative)
    # Runtimes are MediaPipe builds (Apache-2.0, with upstream NOTICE files).
    # Google publishes its MediaPipe task models under Apache-2.0, except the
    # Gemma-based text models, whose Gemma Terms and use-restriction notice
    # must travel with every copy.
    for item in items.values():
        filename = urlsplit(item['urls'][0]).path.rsplit('/', 1)[-1]
        item['license'] = ('Gemma Terms' if filename in GEMMA_MODELS
                           else 'Apache-2.0')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', action='append', default=[],
                        help='Build target such as macos/arm64; repeat as needed')
    parser.add_argument('--prefill', type=Path,
                        help='Fill this SHA-named directory using core downloadVerified')
    args = parser.parse_args()
    items = {}
    runtime_assets(items)
    model_assets(items)
    targets = {part for value in args.target for part in value.split(',')}
    selected = [item for item in items.values()
                if not targets or item['kind'] == 'model'
                or targets.intersection(item['targets'])]
    selected.sort(key=lambda item: (item['kind'], item['sha256']))
    if args.prefill:
        if not targets:
            parser.error('--prefill requires at least one --target')
        args.prefill.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ['dart', 'run', 'mediapipe_core:prefill_assets', str(args.prefill.resolve())],
            input=json.dumps(selected), text=True, check=True,
            cwd=PACKAGES / 'mediapipe-core',
        )
    else:
        for item in selected:
            print(f"{item['kind']} {','.join(item['targets'])} {item['sha256']} "
                  f"{item['release_asset']} license={item['license']} "
                  f"url={item['urls'][0]}")


if __name__ == '__main__':
    main()
