# Migration

Each package's `MIGRATION.md` lists every renamed or removed symbol:
[core](packages/mediapipe-core/MIGRATION.md),
[vision](packages/mediapipe-task-vision/MIGRATION.md),
[text](packages/mediapipe-task-text/MIGRATION.md) and
[audio](packages/mediapipe-task-audio/MIGRATION.md).

## From `mediapipe_flutter_*` (this repository before 0.1.0)

1. Rename the dependencies and imports: `mediapipe_flutter_vision` becomes
   `mediapipe_vision` (`package:mediapipe_vision/mediapipe_vision.dart`), and
   likewise for core, text, audio and genai.
2. Rename the build settings in `pubspec.yaml`:
   `hooks.user_defines.mediapipe_flutter_core` becomes `mediapipe_core`, and
   `mediapipe_flutter_vision` becomes `mediapipe_vision`.
3. Import only each family's main library. Backend factories, bindings and
   the `io.dart`, `web.dart`, `vision_native.dart` entry points are no longer
   for apps; plugin code uses `platform_interface.dart`.
4. Catch `MediaPipeException` (or its subtypes) instead of the per-task
   exception classes; see each package's table.
5. Optionally replace your own model files with Google's pinned ones
   (`model: VisionModels.x`, `TextModels.x` or `AudioModels.yamnet`): list
   them under `hooks.user_defines.<family>.models`, declare
   `assets/mediapipe/` under `flutter: assets:`, and run
   `dart run mediapipe_core:bundle_models`.
6. `model:` no longer downloads at run time by default. Bundle the models as
   in step 5, or set `ModelStore.allowDownloads = true` (from
   `mediapipe_core`) before creating tasks to keep downloading them.

## From Google's `mediapipe_text` 0.0.1

Google's 0.0.1 created tasks with constructors and `BaseOptions`:

```dart
final classifier = TextClassifier(
  TextClassifierOptions.fromAssetPath('assets/bert_classifier.tflite'),
);
```

Now creation is asynchronous, and the model can be a pinned official one:

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<String?> topCategory(String text) async {
  final classifier = await TextClassifier.create(
    TextClassifierOptions(model: TextModels.bertClassifier),
  );
  try {
    final result = await classifier.classify(text);
    return result.classifications.first.categories.first.categoryName;
  } finally {
    await classifier.dispose();
  }
}
```

`TextClassifierOptions.fromAssetBuffer` and `.fromAssetPath` still accept your
own model. Results keep Google's shape (`classifications`, `categories`,
`categoryName`, `score`), `dispose()` is idempotent, and calling a disposed
task throws `StateError`. The text tasks run on Android, iOS, macOS, Linux,
Windows and the web.
