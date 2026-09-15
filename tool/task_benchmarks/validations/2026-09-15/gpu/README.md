# Official macOS GPU probes

`report.json` and the six compressed native logs were produced by
`packages/mediapipe-task-text/tool/probe_text_gpu.py` using the original Google
MediaPipe 1.0.1 macOS arm64 library and pinned official models. Their SHA-256
digests, macOS version and Python version are recorded in the report.

Each task/delegate ran in a separate process with a 120-second timeout. These
are the results obtained outside the restricted tool sandbox, with normal
macOS graphics access. All three CPU controls created a task, returned three
results, and closed successfully.

| Task | GPU outcome |
| --- | --- |
| EmbeddingGemma | Metal delegate creation is logged, but preparation fails: `Input tensor is not found in the graph`. The interpreter cannot be created. |
| Proofreader | Creation rejects the request: `Only CPU delegate is supported.` |
| Summarizer | Creation rejects the request: `Only CPU delegate is supported.` |

EmbeddingGemma's log also lists unsupported operators/tensor shapes, including
EMBEDDING_LOOKUP and an unsupported FULLY_CONNECTED version. This is an official
runtime/model compatibility failure, not a missing Dart delegate switch.

No successful GPU execution or CPU fallback was observed in these probes. The
package continues to reject GPU explicitly. The supported-delegate query and
creation errors expose these reasons. The existing MagicTouch shader issue is
independent and is documented in `packages/mediapipe-task-vision/tool/INTERACTIVE_SEGMENTER.md`.
