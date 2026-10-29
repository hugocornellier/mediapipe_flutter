"""Drop the icon package's weight variants from a gallery web build.

lucide_icons_flutter declares six variable-weight Lucide fonts (about 1.4 MB)
besides the regular one, and Flutter web downloads every declared font before
its first frame. The gallery only draws the regular Lucide icons, so the
variants are removed from build/web's font manifest and deleted.
"""
import json
from pathlib import Path
import re
import sys

web = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web')
manifest = web / 'assets/FontManifest.json'
families = json.loads(manifest.read_text())
variant = re.compile(r'packages/lucide_icons_flutter/Lucide[1-9]00')
kept = [f for f in families if not variant.fullmatch(f['family'])]
removed = 0
for family in families:
    if family in kept:
        continue
    for font in family['fonts']:
        path = web / 'assets' / font['asset']
        removed += path.stat().st_size
        path.unlink()
manifest.write_text(json.dumps(kept, separators=(',', ':')))
print(f'Removed {len(families) - len(kept)} unused icon font variants '
      f'({removed / 1e6:.1f} MB) from {manifest}')
