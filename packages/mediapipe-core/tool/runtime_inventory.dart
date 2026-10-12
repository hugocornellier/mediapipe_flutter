import 'dart:convert';

import 'package:mediapipe_core/native_assets.dart';

/// Prints Google's libraries the hooks bundle, as JSON for
/// `tool/mirror_runtime_assets.py` and the fresh-app harnesses
/// (`tool/consumer_packages.py`): every per-family library `familyRuntimes`
/// pins, and every library `wheelRuntimes` extracts from Google's wheel. A
/// library Google has not published yet has an empty URL. A wheel's entry
/// names the library (`file`, `sha256`) and the wheel the hook downloads
/// (`url`, `wheel_sha256`).
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
      for (final MapEntry(key: family, value: targets) in wheelRuntimes.entries)
        for (final MapEntry(key: target, value: runtime) in targets.entries)
          {
            'family': family,
            'target': target,
            'file': runtime.path.split('/').last,
            'sha256': runtime.sha256,
            'url': runtime.wheel.url,
            'wheel_sha256': runtime.wheel.sha256,
          },
    ]),
  );
}
