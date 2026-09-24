import 'package:flutter/material.dart';

import '../catalog.dart';

/// The audio package has no browser runtime, so no audio tile reaches the
/// browser gallery; this keeps the web build free of its native API.
class AudioPage extends StatelessWidget {
  const AudioPage({super.key, required this.task});

  final GalleryTask task;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(task.title)),
    body: const Center(child: Text('Audio tasks do not run in the browser.')),
  );
}
