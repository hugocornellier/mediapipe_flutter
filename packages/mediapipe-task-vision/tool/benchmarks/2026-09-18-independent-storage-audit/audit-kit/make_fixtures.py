#!/usr/bin/env python3
"""Pre-render the benchmark's BGRA frames once, so every launch replays identical bytes.

Codex's harness rendered the portrait with Flutter at runtime; two launches got
different decoded pixels. Here the letterboxed portrait is produced offline with
Pillow's bilinear resize, stored as raw padded BGRA (row stride = width*4 + 16,
padding bytes 0xA5, alpha 255), and verified by SHA-256 inside the app.
"""
import hashlib, json, sys
from pathlib import Path
from PIL import Image

def render(source, width, height, pad=16):
    image = Image.open(source).convert('RGB')
    scale = min(width / image.width, height / image.height)
    w, h = round(image.width * scale), round(image.height * scale)
    canvas = Image.new('RGB', (width, height), (0, 0, 0))
    canvas.paste(image.resize((w, h), Image.Resampling.BILINEAR), ((width - w) // 2, (height - h) // 2))
    rgb = canvas.tobytes()
    stride = width * 4 + pad
    out = bytearray(b'\xa5' * (stride * height))
    for y in range(height):
        row = rgb[y * width * 3:(y + 1) * width * 3]
        d = y * stride
        out[d:d + width * 4:4] = row[2::3]      # B
        out[d + 1:d + width * 4:4] = row[1::3]  # G
        out[d + 2:d + width * 4:4] = row[0::3]  # R
        out[d + 3:d + width * 4:4] = b'\xff' * width
    return bytes(out), stride

def main():
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    manifest = {'source': source.name, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'fixtures': []}
    for width, height in [(480, 640), (1080, 1920)]:
        data, stride = render(source, width, height)
        name = f'portrait_{width}x{height}_bgra.bin'
        (destination / name).write_bytes(data)
        manifest['fixtures'].append({'file': name, 'width': width, 'height': height, 'stride': stride,
                                     'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    (destination / 'fixtures.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))

if __name__ == '__main__':
    main()
