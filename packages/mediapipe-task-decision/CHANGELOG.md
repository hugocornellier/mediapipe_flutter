## 0.1.0 (unreleased)

Not published yet.

- Decision Maker on Android, iOS, macOS, Linux, Windows and the web, through
  Google's official MediaPipe runtimes: its per-family 1.1.1 decision C
  library everywhere but Windows, the C library from Google's 1.1.0 Python
  wheel there, and `@mediapipe/tasks-decision` in browsers.
- `evaluateBoolean`, `evaluateChoice` and `evaluateScore` with Google's
  `BooleanQuestion`, `ChoiceQuestion` and `ScoreQuestion`, plus their batch
  forms, with the same results on every platform.
- `DecisionModels` pins Google's Laya, GLiNER2.5-Decide and EmbeddingGemma 2
  models; `queryDecisionMakerCapabilities(model)` says where a model runs,
  since Google's per-family library fails every evaluation with the
  text-only EmbeddingGemma 2 (UP-053), and its browser runtime embeds every
  text as zeros with either EmbeddingGemma 2 model in WebKit (UP-054) and
  aborts with GLiNER2.5-Decide in every browser (UP-055).
- In browsers Google's runtime ignores `normalizePrior` and `scoringMode`
  (UP-056), as the questions' documentation says.
