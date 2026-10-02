import 'package:flutter/material.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

/// Display the package's supported backend and explain disabled GPU selection.
class TaskSupport extends StatefulWidget {
  const TaskSupport({super.key, required this.query});

  /// The task's capability query, such as `queryTextSummarizerCapabilities`.
  final Future<TaskCapabilities> Function() query;

  @override
  State<TaskSupport> createState() => _TaskSupportState();
}

class _TaskSupportState extends State<TaskSupport> {
  late final _support = widget.query();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _support,
    builder: (context, snapshot) {
      final support = snapshot.data;
      if (support == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(
                support.isSupported ? 'CPU available' : 'Unsupported platform',
              ),
            ),
            Tooltip(
              message: support.unavailableReasons[Delegate.gpu] ?? '',
              child: const Chip(label: Text('GPU unavailable')),
            ),
          ],
        ),
      );
    },
  );
}
