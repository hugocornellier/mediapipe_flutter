import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'segment_page.dart';
import 'text_page.dart';
import 'audio_page.dart';
import 'live_page.dart';
import 'gallery_assets_io.dart'
    if (dart.library.js_interop) 'web/gallery_assets.dart';
export 'gallery_assets_io.dart'
    if (dart.library.js_interop) 'web/gallery_assets.dart';

SemanticsHandle? _webSemantics;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) _webSemantics ??= WidgetsBinding.instance.ensureSemantics();
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MediaPipe Gallery',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF00897B),
      brightness: Brightness.light,
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF00897B),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<(GalleryAssets, TaskPlatform)> _ready = _load();

  // Every capability query carries the platform snapshot it was evaluated
  // against, so the gallery reads it from the package rather than deriving a
  // second opinion about what it is running on.
  Future<(GalleryAssets, TaskPlatform)> _load() async => (
    await GalleryAssets.unpack(),
    (await queryObjectDetectorCapabilities()).platform,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<(GalleryAssets, TaskPlatform)>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message(
            icon: Icons.error_outline,
            text: 'Could not load the gallery.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (assets, platform) = snapshot.requireData;
        final bundled = assets.bundledTasks;
        final tasks = [
          for (final task in supportedTasks(
            platform,
            bundled,
            assets.officialMacosLandmarkTasks,
          ))
            if (task.hasOwnPage) task,
        ];
        return _Gallery(assets: assets, platform: platform, tasks: tasks);
      },
    ),
  );
}

/// Wider windows keep the catalog at a readable width, centred.
const _maxContentWidth = 1200.0;

/// Each section's accent: a tonal palette from its own hue, so a section's
/// cards read as one family in the light and dark themes alike.
final _accents = <(GalleryCategory, Brightness), ColorScheme>{};

ColorScheme _accent(GalleryCategory category, Brightness brightness) =>
    _accents[(category, brightness)] ??= ColorScheme.fromSeed(
      seedColor: switch (category) {
        GalleryCategory.vision => const Color(0xFF00897B),
        GalleryCategory.audio => const Color(0xFFEF6C00),
        GalleryCategory.text => const Color(0xFF5E35B1),
      },
      brightness: brightness,
    );

IconData _categoryIcon(GalleryCategory category) => switch (category) {
  GalleryCategory.vision => Icons.visibility_outlined,
  GalleryCategory.audio => Icons.graphic_eq,
  GalleryCategory.text => Icons.notes,
};

String _categoryBlurb(GalleryCategory category) => switch (category) {
  GalleryCategory.vision =>
    'Faces, hands, bodies and objects, in the camera and in images.',
  GalleryCategory.audio => 'Sounds in a clip or from the microphone.',
  GalleryCategory.text => 'The language, sentiment and meaning of a text.',
};

IconData _taskIcon(GalleryTask task) => switch (task.runtimeId) {
  'face_detector' => Icons.face_outlined,
  'face_landmarker' => Icons.face_retouching_natural,
  'hand_landmarker' => Icons.back_hand_outlined,
  'gesture_recognizer' => Icons.waving_hand_outlined,
  'pose_landmarker' => Icons.accessibility_new,
  'holistic_landmarker' => Icons.emoji_people,
  'object_detector' => Icons.crop_free,
  'image_classifier' => Icons.sell_outlined,
  'image_embedder' => Icons.scatter_plot_outlined,
  'image_segmenter' => Icons.layers_outlined,
  'interactive_segmenter' => Icons.touch_app_outlined,
  'audio_classifier' => Icons.graphic_eq,
  'language_detector' => Icons.translate,
  'text_classifier' => Icons.sentiment_satisfied_outlined,
  'text_embedder' => Icons.compare_arrows,
  _ => _categoryIcon(task.category),
};

class _Gallery extends StatefulWidget {
  const _Gallery({
    required this.assets,
    required this.platform,
    required this.tasks,
  });

  final GalleryAssets assets;
  final TaskPlatform platform;
  final List<GalleryTask> tasks;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  /// The one section the filter shows, or every section when null.
  GalleryCategory? _only;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = widget.platform;
    final width = MediaQuery.sizeOf(context).width;
    final inset = math.max(16.0, (width - _maxContentWidth) / 2);
    // Phones get one compact row per task; wider windows a grid of cards.
    final compact = width < 600;
    // Tasks this build can run, by section and name; a planned card stands
    // in for each Studio task it cannot.
    final sorted = [...widget.tasks]
      ..sort((a, b) => a.title.compareTo(b.title));
    final validated = [
      for (final task in sorted)
        if (!task.isExperimental) task,
    ];
    final experimental = [
      for (final task in sorted)
        if (task.isExperimental) task,
    ];
    List<GalleryTask> within(List<GalleryTask> list, GalleryCategory c) => [
      for (final task in list)
        if (task.category == c) task,
    ];
    List<PlannedTask> plannedIn(GalleryCategory c) => [
      for (final task in plannedTasks)
        if (task.category == c && !sorted.any((t) => t.title == task.title))
          task,
    ];
    final withGpu = sorted
        .where(
          (task) => task
              .capabilitiesFor(
                platform,
                widget.assets.officialMacosLandmarkTasks,
              )
              .supportedDelegates
              .contains(VisionDelegate.gpu),
        )
        .length;
    final shown = [
      for (final category in GalleryCategory.values)
        if (within(sorted, category).isNotEmpty ||
            plannedIn(category).isNotEmpty)
          category,
    ];
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          centerTitle: false,
          titleSpacing: inset,
          title: Text(
            'MediaPipe Gallery',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actionsPadding: EdgeInsetsDirectional.only(end: inset - 8),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About this build',
              onPressed: () => _showAbout(context),
            ),
          ],
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, 4, inset, 0),
          sliver: SliverToBoxAdapter(
            child: _Intro(
              platform: platform,
              validated: validated.length,
              withGpu: withGpu,
            ),
          ),
        ),
        if (shown.length > 1)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, 20, inset, 0),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _only == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _only = null),
                  ),
                  for (final category in shown)
                    ChoiceChip(
                      avatar: Icon(_categoryIcon(category), size: 18),
                      label: Text(category.title),
                      selected: _only == category,
                      showCheckmark: false,
                      onSelected: (selected) =>
                          setState(() => _only = selected ? category : null),
                    ),
                ],
              ),
            ),
          ),
        for (final category in shown)
          if (_only == null || _only == category) ...[
            _header(theme, category, within(sorted, category).length, inset),
            if (within(validated, category).isNotEmpty)
              _grid(within(validated, category), inset, compact),
            if (within(experimental, category).isNotEmpty) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 4, inset, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Experimental: these run real inference but are not '
                          "validated against Google's outputs on this platform.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _grid(within(experimental, category), inset, compact),
            ],
            if (plannedIn(category) case final planned when planned.isNotEmpty)
              _plannedGrid(planned, inset, compact),
          ],
        if (within(sorted, GalleryCategory.vision).isEmpty &&
            (_only == null || _only == GalleryCategory.vision))
          const SliverToBoxAdapter(
            child: _Message(
              icon: Icons.inbox_outlined,
              text: 'No task has a validated runtime on this platform yet.',
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _header(
    ThemeData theme,
    GalleryCategory category,
    int count,
    double inset,
  ) {
    final accent = _accent(category, theme.brightness);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(inset, 32, inset, 14),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            _IconTile(
              icon: _categoryIcon(category),
              background: accent.primaryContainer,
              foreground: accent.onPrimaryContainer,
              size: 40,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        category.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _categoryBlurb(category),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverGridDelegate _layout(bool compact) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 640 : 380,
        mainAxisExtent: compact ? 92 : 152,
        crossAxisSpacing: 16,
        mainAxisSpacing: compact ? 10 : 16,
      );

  Widget _plannedGrid(List<PlannedTask> entries, double inset, bool compact) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
        sliver: SliverGrid.builder(
          gridDelegate: _layout(compact),
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _PlannedCard(task: entries[index], compact: compact),
        ),
      );

  Widget _grid(List<GalleryTask> entries, double inset, bool compact) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
        sliver: SliverGrid.builder(
          gridDelegate: _layout(compact),
          itemCount: entries.length,
          itemBuilder: (context, index) => _TaskCard(
            task: entries[index],
            platform: widget.platform,
            assets: widget.assets,
            compact: compact,
          ),
        ),
      );

  void _showAbout(BuildContext context) {
    final platform = widget.platform;
    final assets = widget.assets;
    final unvalidated = unvalidatedTasks(
      platform,
      assets.bundledTasks,
      assets.officialMacosLandmarkTasks,
    );
    // Validated here, but with no screen of its own. Without this the task is
    // invisible: absent from the grid and absent from the unvalidated list.
    final pending = [
      for (final task in supportedTasks(
        platform,
        assets.bundledTasks,
        assets.officialMacosLandmarkTasks,
      ))
        if (!task.hasOwnPage) task,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This build', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Target: ${assets.manifest['target']}'),
              Text(
                'Platform: ${platform.operatingSystem} '
                '${platform.architecture}'
                '${platform.version == null ? '' : ' ${platform.version}'}',
              ),
              Text('Bundled runtimes: ${assets.bundledTasks.length}'),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Validated here, demo not built yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                for (final task in pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(task.title),
                  ),
              ],
              if (unvalidated.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Bundled but not validated here',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                for (final entry in unvalidated.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          entry.value,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The platform the catalog was validated on, and what it adds up to.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.platform,
    required this.validated,
    required this.withGpu,
  });

  final TaskPlatform platform;
  final int validated;
  final int withGpu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final os = switch (platform.operatingSystem) {
      'macos' => 'macOS',
      'ios' => 'iOS',
      'android' => 'Android',
      'linux' => 'Linux',
      'windows' => 'Windows',
      'web' => 'Web',
      final other => other,
    };
    final device = switch (platform.operatingSystem) {
      'web' => Icons.language,
      'ios' => Icons.phone_iphone,
      'android' => Icons.phone_android,
      'windows' => Icons.desktop_windows_outlined,
      _ => Icons.laptop_mac,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Google's official MediaPipe tasks, running on this device.",
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              icon: device,
              label: platform.architecture == 'unknown'
                  ? os
                  : '$os · ${platform.architecture}',
            ),
            _Pill(
              icon: Icons.verified_outlined,
              label: '$validated task${validated == 1 ? '' : 's'} validated',
            ),
            if (withGpu > 0)
              _Pill(icon: Icons.bolt, label: '$withGpu with GPU'),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

/// A rounded square holding a task's or a section's icon.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 44,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(icon, size: size * 0.55, color: foreground),
  );
}

/// CPU or GPU, as a small pill; GPU takes the section's accent.
class _DelegateBadge extends StatelessWidget {
  const _DelegateBadge({required this.gpu, required this.accent});

  final bool gpu;
  final ColorScheme accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: gpu
            ? accent.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        gpu ? 'GPU' : 'CPU',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: gpu
              ? accent.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.task,
    required this.platform,
    required this.assets,
    required this.compact,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final GalleryAssets assets;
  final bool compact;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final accent = _accent(task.category, theme.brightness);
    final delegates = task
        .capabilitiesFor(
          widget.platform,
          widget.assets.officialMacosLandmarkTasks,
        )
        .supportedDelegates;
    final icon = _IconTile(
      icon: _taskIcon(task),
      background: accent.primaryContainer,
      foreground: accent.onPrimaryContainer,
    );
    final badges = [
      if (task.experimentalReason case final reason?)
        Tooltip(
          message: reason,
          child: Icon(
            Icons.science_outlined,
            size: 16,
            color: theme.colorScheme.tertiary,
          ),
        ),
      // Every task runs on the CPU; a phone row names only the GPU.
      for (final delegate in delegates)
        if (!widget.compact || delegate == VisionDelegate.gpu)
          _DelegateBadge(gpu: delegate == VisionDelegate.gpu, accent: accent),
    ];
    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final summary = Text(
      task.summary,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: _hovered
                ? accent.primary.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => switch (task.demo) {
                GalleryDemo.live => LivePage(
                  task: task,
                  platform: widget.platform,
                  officialMacosLandmarkTasks:
                      widget.assets.officialMacosLandmarkTasks,
                ),
                GalleryDemo.segment => SegmentPage(
                  task: task,
                  assets: widget.assets,
                ),
                GalleryDemo.text => TextPage(task: task),
                GalleryDemo.audio => AudioPage(task: task),
                // Entries without a screen never reach a tile.
                GalleryDemo.none => throw StateError('${task.id} has no demo'),
              },
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // The badges follow the text in both layouts, so a screen reader
            // announces the title first.
            child: widget.compact
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 2), summary],
                        ),
                      ),
                      ...badges,
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(height: 14),
                          title,
                          const SizedBox(height: 4),
                          summary,
                        ],
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: badges,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A task the gallery lists but cannot run yet, with the reason why.
class _PlannedCard extends StatelessWidget {
  const _PlannedCard({required this.task, required this.compact});

  final PlannedTask task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final icon = _IconTile(
      icon: _categoryIcon(task.category),
      background: theme.colorScheme.surfaceContainerHighest,
      foreground: muted,
    );
    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(color: muted),
    );
    final reason = Row(
      children: [
        Icon(Icons.schedule, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            task.reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: compact
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 4), reason],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const Spacer(),
                  title,
                  const SizedBox(height: 4),
                  Text(
                    task.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 8),
                  reason,
                ],
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
