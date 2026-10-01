// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Package containing core dependencies for MediaPipe's text, vision, and
/// audio-based tasks.
library;

export 'mediapipe_exception.dart';
export 'model_store.dart';
export 'capabilities.dart' show TaskCapabilities, TaskPlatform;
export 'src/extensions.dart';
export 'src/interface/containers.dart' show BaseEmbedding, EmbeddingType;
// TODO: Unify the public API so it is identical on all six platforms (these
// core types differ between native and web today) and consistent across
// vision, text and audio. The differences, target API and phases are in
// tool/API_UNIFICATION.md at the repository root, and
// `git grep -n "API_UNIFICATION.md"` lists every site to revisit.
export 'universal_mediapipe_core.dart'
    if (dart.library.js_interop) 'src/web/mediapipe_core.dart'
    if (dart.library.io) 'src/io/mediapipe_core.dart'
    show
        BaseOptions,
        Category,
        Classifications,
        ClassifierOptions,
        ClassifierResult,
        EmbedderOptions,
        Embedding;
