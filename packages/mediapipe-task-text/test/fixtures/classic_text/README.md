# Official MediaPipe 1.0.1 text references

`official_reference.json` records Google's unmodified macOS arm64 CPU outputs
for the version-1 BERT classifier, Universal Sentence Encoder and language
detector. Model SHA-256 pins also appear in `lib/models.dart`; the reference
generator checks both those models and the original Google library digest.

There are 26 model/option cases, four rejected option configurations, four
cosine comparisons and three repeated-request sequences. Classifier timestamps
advance by 1000 ms per request; the tests preserve these native values.
Floating outputs are compared within 1e-6 and quantized bytes exactly. Local
native outputs match exactly; the measured 1.11e-16 difference is in cosine math.

Hosted macOS 15 runners differ from the macOS 26 physical-Mac baseline: both
the package and fresh Flutter consumer first differed in USE greeting vector
element 4 by `1.2814998626708984e-6`. CI therefore generates an independent
reference using the checksum-pinned official 1.0.1 wheel on each test runner.
The `1e-6` tolerance and exact quantized-byte comparisons remain unchanged.

Run `tool/prepare_classic_text_reference.py` after downloading the three models,
then set `MEDIAPIPE_CLASSIC_TEXT_REFERENCE_DIR` to its absolute output directory
(`build/classic-text-reference` at the repository root by default). The package
suite and fresh-app test both require a receipt matching the official library,
wheel, model and baseline hashes. Missing or modified outputs fail. Without an
override, local tests continue using the checked-in baseline. The generator
records host differences and refuses structural changes; CI uploads the
reference, receipt and official Python log for review. Python is used only to
prepare expected outputs; it remains blocked inside consumer builds.

Regenerate using `tool/generate_classic_text_reference.py --python-package-root`
with the extracted, pinned MediaPipe 1.0.1 wheel. `--output` writes elsewhere
without replacing the reviewed fixture. Do not generate expected values
from the Dart implementation. Test sentences were written for this fixture.
