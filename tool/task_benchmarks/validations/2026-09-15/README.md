# Modern macOS task audit — 2026-09-15

Validated on Apple M4 Max with 48 GiB RAM,
macOS 26.4, using an AOT native-assets consumer and
the official MediaPipe 1.0.1 CPU runtime. The source checkout was clean at
`6a6479751746c2994977ce1abbc579f2b99cf354`. Exact source, executable and reference digests
are recorded in the reports. The benchmark finished at 2026-09-15T09:40:58.539327Z.

All **97 option/input cases passed**, including separate official streaming
references, token-limit errors and recovery. All four tasks stayed loaded for
**1,000 measured iterations each (4,000 calls)** after warmups. Each task also
passed **25 create/infer/dispose cycles**, and MagicTouch passed 25 image-reset
cycles. Both generated-text caches were populated and reused without rewriting
the cache files; output remained identical.

| Task / API | Samples | Median ms | p95 ms |
| --- | ---: | ---: | ---: |
| embedding / completed | 1000 | 124.95 | 127.34 |
| proofreader / completed | 500 | 46.49 | 48.30 |
| proofreader / streaming | 500 | 46.86 | 48.75 |
| summarizer / completed | 500 | 40.64 | 42.28 |
| summarizer / streaming | 500 | 40.91 | 42.51 |
| segmenter / completed | 1000 | 191.36 | 195.49 |

These are wall-clock public API latencies including worker messaging and result
copies, with reference comparison outside the timer. Text workloads use the
recorded short inputs; Summarizer uses TLDR mode. Segmentation uses the official
299 × 150 RGB fixture and one positive stroke. These measurements are a baseline,
not a claim that every setting or input runs at the same speed.

Process RSS ranged from **954.7 to 1031.3 MiB**
during sustained inference. The first/last 100-sample medians were
**1030.8 / 964.9 MiB**.
RSS includes model maps, native caches, allocator retention and Dart GC. The raw
report preserves every memory sample and each reload sample; this finite run
does not establish leak freedom for every workload.

## Additional validation

- Six new capability tests and 32 existing modern text regression tests passed.
- Four actual macOS Flutter demo integration tests passed, including changing
  embedding output options, retrieval roles, summary mode and token budgets.
- The macOS release demo build passed.
- Existing MagicTouch mask/lifecycle tests passed, including padded image inputs
  and coexistence with the CPU/Metal face tasks.

## Upstream behavior preserved

The [official GPU probes](gpu/README.md) confirm all three text GPU blockers.
No GPU backend was enabled. MagicTouch's separate shader failure is unchanged.

Long-input tests found that undersized token budgets can reject input, and the
streaming error can include an additional native status prefix. Both error
forms are captured independently and compared exactly.

`official-summary-history.json` records an independent Python probe on the long
KEYPOINTS fixture: a fresh task produced “Renovations begin”, while the first
long request after short completed/streamed requests produced “Renovations start”.
Later repetitions again produced “begin”. Dart reproduced the fresh output;
the matrix replays the generator's exact preceding requests and matches its
completed/streaming outputs. No text rewriting or fuzzy comparison is used.

The oversized EmbeddingGemma case preserves Google's inference and close errors.
Its Python reference runs in a bounded process to avoid the failed handle's
finalizer being invoked again. The Dart wrapper closes its owned handle once.

See [the runner documentation](../../README.md) for reproduction. `summary.json`
contains compact measurements, `report.json.gz` contains every sample and check,
and the compressed build/native logs retain the full execution record.
