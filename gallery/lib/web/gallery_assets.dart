import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Browser assets are served directly rather than unpacked to filesystem paths.
final class GalleryAssets {
  const GalleryAssets(this.manifest);
  final Map<String, dynamic> manifest;
  Set<String> get bundledTasks =>
      (manifest['tasks'] as List).cast<String>().toSet();
  Set<String> get officialMacosLandmarkTasks =>
      (manifest['official_macos_landmark_tasks'] as List)
          .cast<String>()
          .toSet();
  String path(String name) {
    final group = (manifest['models'] as Map).values.contains(name)
        ? 'models'
        : 'samples';
    return Uri.base.resolve('assets/assets/$group/$name').toString();
  }

  ImageProvider imageProvider(String name) => NetworkImage(path(name));

  static Future<GalleryAssets> unpack() async => GalleryAssets(
    jsonDecode(await rootBundle.loadString('assets/manifest.json'))
        as Map<String, dynamic>,
  );
}
