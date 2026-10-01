# Image Embedder samples

The gallery's Image Embedder page compares these photos, the three that
Google's own Image Embedding demo offers. They are copied unchanged from
[google-ai-edge/mediapipe-samples-web](https://github.com/google-ai-edge/mediapipe-samples-web/tree/0e0e059183983b4eb0e9316e00b0e2e937c8b11e/public)
at revision `0e0e059183983b4eb0e9316e00b0e2e937c8b11e`. That repository is
licensed under the Apache License 2.0, preserved in
[SOURCE_LICENSE](SOURCE_LICENSE).

| File | Source path | Size | SHA-256 |
| --- | --- | --- | --- |
| `dog.jpg` | `public/dog.jpg` | 640 x 640 | `87295aa79a9e285f86a94c58230c50401453dbc8cca946d544ce0e3de3f71cf7` |
| `cat.png` | `public/cat.png` | 640 x 640 | `e8383ad9f9be84a62cb18ae2be6d6d89e478663385bcec9ffe5d82f6db3fd4d5` |
| `elephant.png` | `public/elephant.png` | 640 x 640 | `9caa818cdde183d09c56b2f56d4a26b9e54fb78074040be0c819cff91c11c098` |

Unchanged files give the same similarities as Google's demo for the same
model and delegate. The gallery's preparer, `tool/gallery_builder` or
`tool/prepare.py`, copies them into the app's samples whenever a build
bundles Image Embedder.
