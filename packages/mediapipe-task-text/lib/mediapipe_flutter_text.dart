// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Package containing MediaPipe's text-specific tasks.
library mediapipe_flutter_text;

export 'universal_mediapipe_flutter_text.dart'
    if (dart.library.html) 'src/web/mediapipe_flutter_text.dart'
    if (dart.library.io) 'src/io/mediapipe_flutter_text.dart';
