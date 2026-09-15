import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_text/capabilities.dart';

/// Display the package's supported backend and explain disabled GPU selection.
class TaskSupport extends StatefulWidget {
  const TaskSupport({super.key, required this.task});

  final TextTask task;

  @override
  State<TaskSupport> createState() => _TaskSupportState();
}

class _TaskSupportState extends State<TaskSupport> {
  late final _support = queryTextTaskCapabilities(widget.task);

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
              message: support.unavailableReasons[TextDelegate.gpu] ?? '',
              child: const Chip(label: Text('GPU unavailable')),
            ),
          ],
        ),
      );
    },
  );
}
