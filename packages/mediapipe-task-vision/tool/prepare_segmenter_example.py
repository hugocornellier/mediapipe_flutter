#!/usr/bin/env python3
"""Copy downloaded model and attributed fixtures into the optional example."""

from pathlib import Path
import shutil

PACKAGE = Path(__file__).resolve().parent.parent
ASSETS = PACKAGE / "example_segmenter/assets"
FILES = {
    "models/interactive_segmentation.task": "interactive_segmentation.task",
    "test/fixtures/interactive_segmentation/cats_and_dogs.jpg": "animals.jpg",
    "test/fixtures/face_detection/landmark-ex1.jpg": "portrait.jpg",
}


def main():
    for source in FILES:
        if not (PACKAGE / source).is_file():
            raise SystemExit(
                f"Missing {source}. Run dart tool/download_interactive_segmenter.dart "
                "and check out the test fixtures."
            )
    ASSETS.mkdir(parents=True, exist_ok=True)
    for source, destination in FILES.items():
        shutil.copyfile(PACKAGE / source, ASSETS / destination)
        print(f"Prepared {destination}")


if __name__ == "__main__":
    main()
