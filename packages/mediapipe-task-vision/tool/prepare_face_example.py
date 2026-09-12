"""Copy the pinned models and canonical test fixtures into the Flutter example."""
from pathlib import Path
import shutil

PACKAGE = Path(__file__).resolve().parents[1]


def prepare():
    assets = PACKAGE / 'example/assets'
    assets.mkdir(parents=True, exist_ok=True)
    for name in ('blaze_face_short_range.tflite', 'face_landmarker.task'):
        source = PACKAGE / 'models' / name
        if not source.exists():
            raise SystemExit(f'Missing {source}; run the model download tools first.')
        shutil.copyfile(source, assets / name)
    for name in ('face_detection', 'face_landmarker'):
        shutil.copytree(PACKAGE / 'test/fixtures' / name,
                        assets / 'fixtures' / name, dirs_exist_ok=True)
    print(f'Prepared models and fixture assets in {assets}')


if __name__ == '__main__':
    prepare()
