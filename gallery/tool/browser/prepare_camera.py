"""Generate face/blank/face browser-webcam input from the existing licensed fixture."""
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[3]
output = Path(sys.argv[1]) if len(sys.argv) > 1 else repo / 'build/codex-tmp/web-camera.y4m'
output.parent.mkdir(parents=True, exist_ok=True)
portrait = repo / 'gallery/assets/samples/portrait.jpg'
filter_chain = (
    '[0:v]scale=640:480:force_original_aspect_ratio=decrease,'
    'pad=640:480:(ow-iw)/2:(oh-ih)/2,format=yuv420p,setsar=1[f0];'
    '[2:v]scale=640:480:force_original_aspect_ratio=decrease,'
    'pad=640:480:(ow-iw)/2:(oh-ih)/2,format=yuv420p,setsar=1[f2];'
    '[f0][1:v][f2]concat=n=3:v=1:a=0[out]'
)
subprocess.run([
    'ffmpeg', '-n', '-hide_banner', '-loglevel', 'error',
    '-loop', '1', '-framerate', '10', '-t', '3', '-i', str(portrait),
    '-f', 'lavfi', '-t', '3', '-i', 'color=black:s=640x480:r=10',
    '-loop', '1', '-framerate', '10', '-t', '3', '-i', str(portrait),
    '-filter_complex', filter_chain, '-map', '[out]',
    '-r', '10', '-pix_fmt', 'yuv420p', str(output),
], check=True)
with output.open('rb') as fixture:
    header = fixture.readline().decode('ascii').strip()
if not all(field in header.split() for field in ('W640', 'H480', 'F10:1', 'C420jpeg')):
    raise RuntimeError(f'Unsupported Chrome Y4M camera header: {header}')
print(f'Prepared Chrome webcam fixture: {header}; {output.stat().st_size} bytes')
