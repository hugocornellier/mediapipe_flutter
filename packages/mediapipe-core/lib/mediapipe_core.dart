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
