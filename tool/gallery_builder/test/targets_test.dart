import 'dart:io';

import 'package:gallery_builder/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The vision package's runtime table, which this tool cannot import.
final _sdkDownloads = File(
  p.join('..', '..', 'packages', 'mediapipe-task-vision', 'sdk_downloads.dart'),
).readAsStringSync();

/// The quoted names in the first `{...}` set literal after [start].
Set<String> _setAfter(String source, int start) {
  final open = source.indexOf('{', start);
  return RegExp(r"'(\w+)'")
      .allMatches(source.substring(open, source.indexOf('}', open)))
      .map((match) => match.group(1)!)
      .toSet();
}

void main() {
  test('every task a target bundles has a pinned model', () {
    for (final MapEntry(key: target, value: tasks) in targetTasks.entries) {
      expect(models.keys, containsAll(tasks), reason: target);
    }
  });

  test('the macOS engine tasks match sdk_downloads.dart', () {
    expect(
      _setAfter(_sdkDownloads, _sdkDownloads.indexOf('const macosEngineTasks')),
      macosEngineTasks,
    );
  });

  // A fresh checkout has no maintainer build, so an unpublished row's task
  // would fail the build hook rather than appear as a tile.
  test('macOS bundles the engine tasks and published macOS source builds', () {
    final releases = _sdkDownloads.substring(
      _sdkDownloads.indexOf('const visionRuntimeReleases'),
      _sdkDownloads.indexOf('const visionWheelReleases'),
    );
    final published = <String>{
      for (final row in releases.split('VisionRuntimeRelease(').skip(1))
        if (row.contains("target: 'macos/arm64'") &&
            !row.contains('archive: null'))
          ..._setAfter(row, row.indexOf('tasks:')),
    };
    expect(published, isNotEmpty);
    expect(macosTasks.difference(nonVisionTasks), {
      ...macosEngineTasks,
      ...published,
    });
  });
}
