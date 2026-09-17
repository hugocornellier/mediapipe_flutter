import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'main.dart';
import 'runners.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.task,
    required this.platform,
    required this.assets,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final GalleryAssets assets;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  late List<VisionDelegate> _delegates;
  late VisionDelegate _delegate;
  Future<List<ResultRow>>? _pending;

  @override
  void initState() {
    super.initState();
    _delegates = widget.task
        .capabilities(widget.platform)
        .supportedDelegates
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    _delegate = _delegates.first;
    _run();
  }

  void _run() {
    final runner = runnerFor(widget.task.id)!;
    setState(() {
      _pending = runner(
        widget.assets.path(widget.task.model),
        widget.assets.path(widget.task.sample),
        _delegate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.task.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            widget.task.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(widget.assets.path(widget.task.sample)),
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          if (_delegates.length > 1)
            SegmentedButton<VisionDelegate>(
              segments: [
                for (final delegate in _delegates)
                  ButtonSegment(
                    value: delegate,
                    label: Text(delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'),
                  ),
              ],
              selected: {_delegate},
              onSelectionChanged: (selection) {
                _delegate = selection.first;
                _run();
              },
            ),
          const SizedBox(height: 16),
          FutureBuilder<List<ResultRow>>(
            future: _pending,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Card.filled(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${snapshot.error}',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Card.filled(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      for (final (label, value) in snapshot.requireData)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  value,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _run,
              icon: const Icon(Icons.refresh),
              label: const Text('Run again'),
            ),
          ),
        ],
      ),
    );
  }
}
