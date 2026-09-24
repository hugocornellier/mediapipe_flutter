import 'package:flutter/material.dart';

import '../catalog.dart';

/// The text package has no browser runtime, so no text tile reaches the
/// browser gallery; this keeps the web build free of its native API.
class TextPage extends StatelessWidget {
  const TextPage({super.key, required this.task});

  final GalleryTask task;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(task.title)),
    body: const Center(child: Text('Text tasks do not run in the browser.')),
  );
}
