import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'task_models.dart';
import 'task_settings.dart';

/// A task's settings and delegate, laid out as MediaPipe Studio shows them.
///
/// Sliders report a value once the drag ends, so a task is rebuilt once per
/// change rather than once per pixel dragged.
class TaskSettingsPanel extends StatefulWidget {
  const TaskSettingsPanel({
    super.key,
    required this.settings,
    required this.values,
    required this.delegates,
    required this.delegate,
    required this.enabled,
    required this.onChanged,
    required this.onDelegate,
    required this.models,
    required this.model,
    required this.uploaded,
    required this.modelStatus,
    required this.onModel,
    required this.onUpload,
    this.connections = false,
    this.points = false,
    this.onConnections,
    this.onPoints,
  });

  /// Overlay display: skeleton or box outlines, and individual points. Pages
  /// without an overlay, such as the text demos, leave these null.
  final bool connections;
  final bool points;
  final ValueChanged<bool>? onConnections;
  final ValueChanged<bool>? onPoints;

  /// Google's other official models for the task; the bundled one is
  /// "Standard".
  final List<TaskModel> models;

  /// The chosen official model, or null for the standard or uploaded one.
  final TaskModel? model;

  /// The uploaded file's name while an upload is chosen.
  final String? uploaded;

  /// A download in progress or a model that failed to load.
  final String? modelStatus;
  final void Function(TaskModel? model) onModel;
  final VoidCallback onUpload;

  final List<TaskSetting> settings;
  final TaskSettingValues values;
  final List<VisionDelegate> delegates;
  final VisionDelegate delegate;

  /// False while the task is being rebuilt.
  final bool enabled;
  final void Function(String key, Object value) onChanged;
  final void Function(VisionDelegate delegate) onDelegate;

  @override
  State<TaskSettingsPanel> createState() => _TaskSettingsPanelState();
}

class _TaskSettingsPanelState extends State<TaskSettingsPanel> {
  /// A slider's position while it is being dragged, before it applies.
  final _dragging = <String, double>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Model Selection', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.grid_view, size: 18),
              label: const Text('Standard'),
              selected: widget.model == null && widget.uploaded == null,
              onSelected: widget.enabled ? (_) => widget.onModel(null) : null,
            ),
            for (final model in widget.models)
              ChoiceChip(
                label: Text(
                  '${model.name} · '
                  '${(model.bytes / 1e6).toStringAsFixed(1)} MB',
                ),
                selected: widget.model == model,
                onSelected: widget.enabled
                    ? (_) => widget.onModel(model)
                    : null,
              ),
            ChoiceChip(
              avatar: const Icon(Icons.upload, size: 18),
              label: Text(widget.uploaded ?? 'Upload'),
              selected: widget.uploaded != null,
              onSelected: widget.enabled ? (_) => widget.onUpload() : null,
            ),
          ],
        ),
        if (widget.modelStatus case final status?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(status, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        if (widget.settings.isNotEmpty) ...[
          Text('Settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final setting in widget.settings) _row(setting, theme),
          const SizedBox(height: 16),
        ],
        if (widget.onConnections != null) ...[
          Text('Display', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Connections', style: theme.textTheme.bodyMedium),
            value: widget.connections,
            onChanged: widget.onConnections,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Points', style: theme.textTheme.bodyMedium),
            value: widget.points,
            onChanged: widget.onPoints,
          ),
          const SizedBox(height: 16),
        ],
        Text('Delegate', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // A single delegate is stated rather than offered as a choice.
        if (widget.delegates.length < 2)
          Text(
            '${widget.delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'} only on '
            'this platform',
            style: theme.textTheme.bodyMedium,
          )
        else
          SegmentedButton<VisionDelegate>(
            segments: [
              for (final delegate in widget.delegates)
                ButtonSegment(
                  value: delegate,
                  label: Text(delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'),
                ),
            ],
            selected: {widget.delegate},
            onSelectionChanged: widget.enabled
                ? (selection) => widget.onDelegate(selection.first)
                : null,
          ),
      ],
    );
  }

  Widget _row(TaskSetting setting, ThemeData theme) => switch (setting) {
    CountSetting() => _labelled(
      setting.label,
      '${widget.values.count(setting.key)}',
      theme,
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Fewer',
            onPressed:
                widget.enabled && widget.values.count(setting.key) > setting.min
                ? () => widget.onChanged(
                    setting.key,
                    widget.values.count(setting.key) - 1,
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'More',
            onPressed:
                widget.enabled && widget.values.count(setting.key) < setting.max
                ? () => widget.onChanged(
                    setting.key,
                    widget.values.count(setting.key) + 1,
                  )
                : null,
          ),
        ],
      ),
    ),
    ShareSetting() => _labelled(
      setting.label,
      (_dragging[setting.key] ?? widget.values.share(setting.key))
          .toStringAsFixed(2),
      theme,
      // Flutter 3.47's Slider keeps its value-bubble overlay entry shown at
      // all times. In the page's overlay, each entry becomes a page-sized web
      // semantics node that swallows every click, so each slider gets an
      // overlay of its own. The value is printed beside the label instead.
      Overlay.wrap(
        alwaysSizeToContent: true,
        child: Slider(
          showValueIndicator: ShowValueIndicator.never,
          value: _dragging[setting.key] ?? widget.values.share(setting.key),
          divisions: 20,
          onChanged: widget.enabled
              ? (value) => setState(() => _dragging[setting.key] = value)
              : null,
          onChangeEnd: widget.enabled
              ? (value) {
                  setState(() => _dragging.remove(setting.key));
                  // Twentieths, so 0.35 is not applied as 0.35000000000000003.
                  widget.onChanged(setting.key, (value * 20).round() / 20);
                }
              : null,
        ),
      ),
    ),
    SwitchSetting() => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(setting.label, style: theme.textTheme.bodyMedium),
      value: widget.values.on(setting.key),
      onChanged: widget.enabled
          ? (value) => widget.onChanged(setting.key, value)
          : null,
    ),
  };

  Widget _labelled(
    String label,
    String value,
    ThemeData theme,
    Widget control,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
        control,
      ],
    ),
  );
}
