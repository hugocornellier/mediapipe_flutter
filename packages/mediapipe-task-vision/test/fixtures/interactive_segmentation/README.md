# Interactive Segmenter references

`cats_and_dogs.jpg` is the unchanged sample image used by Google's
[official notebook](https://github.com/google-ai-edge/mediapipe-samples/blob/main/examples/interactive_segmentation/python/interactive_segmenter.ipynb),
downloaded from `https://storage.googleapis.com/mediapipe-assets/cats_and_dogs.jpg`.
Its URL and SHA-256 are recorded in `official_reference.json`.

The raw RGB input is the official JPEG decode sampled at every fourth row and
column, cropped to 299 columns. It intentionally has an odd width for padding
tests. Reference masks are little-endian float32, losslessly gzip-compressed.
The report records uncompressed hashes, dimensions, exact complete stroke
histories and native/API/model provenance. The models are never modified.

Regenerate with `tool/generate_interactive_segmenter_reference.py` using a
separate Python environment containing the official `mediapipe==1.0.1` macOS
ARM64 wheel. The generator refuses a different native library or model hash.
It can also import an extracted wheel using `--python-package-root`.

Coverage includes file and raw inputs, repeated requests, partial strokes,
multiple positive strokes, negative strokes, lasso, undo by resubmitting a
shorter history, RGBA, blank input and image replacement. The blank image
produces a nonempty mask with this official model; references preserve that
behavior. Timings here are observations from reference generation, not warmed
Flutter performance benchmarks.

An empty stroke list fails inside Google's decoder graph and leaves it in an
error state until the image is reset. The Dart API must reject this input before
native calls. GPU initialization in the official macOS wheel fails because the
stroke calculator requests GLSL 330 in its OpenGL 2.1 context. CPU is the only
qualified backend for this runtime; do not silently fall back from GPU.
