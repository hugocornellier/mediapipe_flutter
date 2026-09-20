"""Download the existing face model using the vision package's pinned metadata."""
import hashlib
from pathlib import Path
import re
import urllib.request

vision = Path(__file__).resolve().parents[2] / 'mediapipe-task-vision'
source = (vision / 'lib/models.dart').read_text()
block = re.search(r"const faceLandmarkerUrl\s*=\s*((?:'[^']*'\s*)+);", source).group(1)
url = ''.join(re.findall(r"'([^']*)'", block))
expected = re.search(r"const faceLandmarkerSha256\s*=\s*'([0-9a-f]{64})';", source).group(1)
destination = vision / 'models/face_landmarker.task'
if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != expected:
    data = urllib.request.urlopen(url, timeout=120).read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise RuntimeError('Official face model checksum mismatch')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
print(f'Verified official face model: {expected}')
