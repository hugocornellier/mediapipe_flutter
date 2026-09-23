import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

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
  });

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
        if (widget.settings.isNotEmpty) ...[
          Text('Settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final setting in widget.settings) _row(setting, theme),
          const SizedBox(height: 16),
        ],
        Text('Delegate', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<VisionDelegate>(
          segments: [
            for (final delegate in widget.delegates)
              ButtonSegment(
                value: delegate,
                label: Text(delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'),
              ),
          ],
          selected: {widget.delegate},
          onSelectionChanged: widget.enabled && widget.delegates.length > 1
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
      Slider(
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
