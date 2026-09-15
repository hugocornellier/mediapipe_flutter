# Modern macOS task validation and benchmarks

This maintainer tool exercises the public Dart APIs for EmbeddingGemma,
Proofreader, Summarizer and stateful MagicTouch using the pinned MediaPipe 1.0.1
runtime. It builds a native AOT executable with `dart build cli`; no Bazel,
CMake or custom inference implementation is involved.

From the repository root, run:

```sh
make test_modern_task_matrix
```

After the models have been downloaded, select a longer run and an output folder:

```sh
python3 -B tool/task_benchmarks/run_macos.py \
  --output build/task-benchmarks/long-run \
  --iterations 1000 --reloads 25 --timeout 1200
```

The wrapper retains build logs, native logs, `provenance.json`, and `report.json`.
It enforces a process timeout and exits unsuccessfully on a failed assertion,
native crash, timeout or missing result. Provenance records the chip, memory,
revision, dirty-tree flag, and hashes of the runner source and compiled binary.
Use an otherwise idle Mac for comparable measurements. CI uploads its results
but does not impose hardware-dependent latency or RSS thresholds.

## Coverage

- 97 independently generated official reference cases: all four combinations of
  embedding normalization/quantization across 15 inputs/formats, one oversized
  embedding input, and short/long text across six token budgets for Proofreader
  and both Summarizer modes. Both completed and streaming text APIs are checked.
  Long text cases replay the reference generator's preceding short completed
  and streamed requests. The official Summarizer can change wording depending
  on previous requests; its completed and streaming references are recorded
  independently. No fuzzy text matching is used.
- Floating-point vectors and every mask pixel use an absolute tolerance of
  `1e-6`. Quantized bytes, generated text and proofreading corrections match
  exactly. Expected native errors are checked rather than treated as successes.
- Three warmups followed by repeated inference with all four tasks alive,
  alternating completed and streamed generation. Every output is validated.
- Separate task creation, first segmentation, repeated segmentation, image reset
  plus first segmentation, and create/infer/dispose measurements.
- Process RSS/peak RSS samples during sustained use and after each reload.
  These include model mappings, native allocators and Dart GC. A finite run or
  stable RSS is not proof that every workload is leak-free.
- Fresh explicit cache directories followed by reopening with the same cache;
  results must match and existing cache files must retain size and modification
  time. Generated caches are retained under `build/task-benchmarks` for inspection.
- Explicit text GPU requests must fail with the capability query's explanation.

The timing interval covers the public async inference call, including worker
messaging and result copying. Reference comparison is outside that interval.
Summary/proofreading throughput depends on input and output length; reported
latencies use the short fixture text. Cold cache creation is measured separately
from warmed inference. The report includes all samples, median and p95.

## Official reference provenance

`fixtures/options-reference.json.gz` is lossless JSON generated from Google's
unmodified Python 1.0.1 API and original macOS arm64 dylib. The generator verifies
the original library and all model hashes. It leaves the existing package
fixtures unchanged. The segmentation input and mask come from the vision
package's attributed official fixtures.

```sh
build/codex-tmp/mediapipe-reference/bin/python -B \
  tool/task_benchmarks/generate_reference.py \
  --python-package-root build/codex-tmp/segmenter-wheel \
  --output tool/task_benchmarks/fixtures/options-reference.json.gz
```

Reference generation needs a Python environment with the official wheel's
dependencies and an extracted, hash-verified 1.0.1 wheel. Normal validation uses
the saved references and has no MediaPipe Python dependency. The intentionally
failed EmbeddingGemma graph is generated in a bounded child process: Google's
Python finalizer can attempt to close the failed native handle again. The Dart
wrapper reports the original error and owns its handle's close operation once.

## GPU investigation

Run the official API independently from the Dart wrapper:

```sh
build/codex-tmp/mediapipe-reference/bin/python -B \
  packages/mediapipe-task-text/tool/probe_text_gpu.py \
  --python-package-root build/codex-tmp/segmenter-wheel \
  --output build/task-benchmarks/gpu-probe
```

Run this with normal macOS graphics access. A restricted environment can fail
before reaching the actual GPU backend. Each CPU/GPU request runs in a separate
process with a timeout; CPU controls must pass. Successful output alone would
not establish GPU execution, so native delegate-selection logs are retained.

The pinned runtime rejects Proofreader and Summarizer GPU requests with
`Only CPU delegate is supported.` EmbeddingGemma reaches Metal but fails delegate
preparation with `Input tensor is not found in the graph`; its log also lists
unsupported operators and tensor shapes. MagicTouch's separate GLSL shader
failure is documented in the vision package. All four remain CPU-only in this
package. Changing that requires a working official runtime/pipeline and new
GPU reference, lifecycle and integration validation.
