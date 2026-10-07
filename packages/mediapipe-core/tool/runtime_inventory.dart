import 'dart:convert';

import 'package:mediapipe_core/native_assets.dart';

/// Prints Google's per-family libraries, as `familyRuntimes` pins them, as
/// JSON for `tool/mirror_runtime_assets.py` and the fresh-app harnesses
/// (`tool/consumer_packages.py`). A library Google has not published yet has
/// an empty URL.
void main() {
  print(
    jsonEncode([
      for (final MapEntry(key: family, value: targets)
          in familyRuntimes.entries)
        for (final MapEntry(key: target, value: runtime) in targets.entries)
          {
            'family': family,
            'target': target,
            'file': runtime.fileName,
            'sha256': runtime.sha256,
            'url': runtime.asset.url,
          },
    ]),
  );
}
