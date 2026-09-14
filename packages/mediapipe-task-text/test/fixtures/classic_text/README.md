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

Regenerate using `tool/generate_classic_text_reference.py --python-package-root`
with the extracted, pinned MediaPipe 1.0.1 wheel. Do not generate expected values
from the Dart implementation. Test sentences were written for this fixture.
