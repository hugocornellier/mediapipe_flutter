import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Assets unpacked to real files, because the native tasks read paths.
final class GalleryAssets {
  const GalleryAssets(this.directory, this.manifest);

  final Directory directory;
  final Map<String, dynamic> manifest;

  Set<String> get bundledTasks =>
      (manifest['tasks'] as List).cast<String>().toSet();

  Set<String> get officialMacosLandmarkTasks =>
      (manifest['official_macos_landmark_tasks'] as List)
          .cast<String>()
          .toSet();

  String path(String name) => '${directory.path}/$name';

  File file(String name) => File(path(name));

  ImageProvider imageProvider(String name) => FileImage(file(name));

  static Future<GalleryAssets> unpack() async {
    final directory = await Directory.systemTemp.createTemp(
      'mediapipe-gallery-',
    );
    final manifest =
        jsonDecode(await rootBundle.loadString('assets/manifest.json'))
            as Map<String, dynamic>;
    for (final group in ['models', 'samples']) {
      final names = group == 'models'
          ? (manifest['models'] as Map).values.cast<String>()
          : (manifest['samples'] as List).cast<String>();
      for (final name in names) {
        final bytes = await rootBundle.load('assets/$group/$name');
        await File('${directory.path}/$name').writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    }
    return GalleryAssets(directory, manifest);
  }
}
