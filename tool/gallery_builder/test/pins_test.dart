import 'dart:io';

import 'package:gallery_builder/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Each package's `lib/models.dart`, with adjacent string literals joined so
/// a URL split across lines reads as one literal.
String _pins(String package) {
  final source = File(
    p.join('..', '..', 'packages', package, 'lib', 'models.dart'),
  ).readAsStringSync();
  return source.replaceAll(RegExp(r"'\s*\n\s*'"), '');
}

void main() {
  for (final MapEntry(key: task, value: model) in models.entries) {
    test('$task pins the same model as ${packageOf(task)}', () {
      final pins = _pins(packageOf(task));
      final url = RegExp.escape("'${model.url}'");
      final sha = RegExp.escape("'${model.sha256}'");
      // `const nameUrl = ...; const nameSha256 = ...;` in vision and audio,
      // `DownloadAsset(url: ..., sha256: ...)` in text.
      final named = RegExp('const (\\w+)Url =\\s*$url;').firstMatch(pins);
      final paired =
          (named != null &&
              RegExp(
                'const ${named.group(1)}Sha256 =\\s*$sha;',
              ).hasMatch(pins)) ||
          RegExp('url:\\s*$url,\\s*sha256:\\s*$sha').hasMatch(pins);
      expect(
        paired,
        isTrue,
        reason:
            '${model.url} with ${model.sha256} is not pinned in '
            'packages/${packageOf(task)}/lib/models.dart',
      );
    });
  }
}
