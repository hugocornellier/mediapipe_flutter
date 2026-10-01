// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Package containing MediaPipe's text-specific tasks.
library;

export 'models.dart' show TextModels;
export 'package:mediapipe_core/mediapipe_core.dart'
    show
        BaseEmbedding,
        BaseOptions,
        Category,
        Classifications,
        ClassifierOptions,
        EmbedderOptions,
        Embedding,
        EmbeddingType;
export 'package:mediapipe_core/mediapipe_exception.dart';
export 'src/interface/text_task_exception.dart';
export 'embedding_gemma.dart';
export 'text_proofreader.dart';
export 'text_summarizer.dart';

// TODO: Make this API identical on every platform and flatten the classic
// tasks' options. See tool/API_UNIFICATION.md at the repository root.
export 'universal_mediapipe_text.dart'
    if (dart.library.js_interop) 'src/web/mediapipe_text.dart'
    if (dart.library.io) 'src/io/mediapipe_text.dart';
