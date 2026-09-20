import 'package:flutter/material.dart';
import '../catalog.dart';
import 'gallery_assets.dart';

/// The catalog excludes unsupported browser segmentation tasks.
class SegmentPage extends StatelessWidget {
  const SegmentPage({super.key, required this.task, required this.assets});
  final GalleryTask task;
  final GalleryAssets assets;
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text('Interactive segmentation is unavailable on web.'),
    ),
  );
}
