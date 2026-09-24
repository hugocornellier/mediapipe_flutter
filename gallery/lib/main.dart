import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'segment_page.dart';
import 'text_page.dart' if (dart.library.js_interop) 'web/text_page.dart';
import 'audio_page.dart' if (dart.library.js_interop) 'web/audio_page.dart';
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

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.assets,
    required this.platform,
    required this.tasks,
  });

  final GalleryAssets assets;
  final TaskPlatform platform;
  final List<GalleryTask> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tasks this build can run, by section and name; a planned card stands
    // in for each Studio task it cannot.
    final sorted = [...tasks]..sort((a, b) => a.title.compareTo(b.title));
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
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('MediaPipe Gallery'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About this build',
              onPressed: () => _showAbout(context),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              '${validated.length} task${validated.length == 1 ? '' : 's'} '
              'validated on ${platform.operatingSystem} '
              '${platform.architecture}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        for (final category in GalleryCategory.values) ...[
          _header(theme, category.title),
          if (within(validated, category).isNotEmpty)
            _grid(within(validated, category), platform),
          if (within(experimental, category).isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Experimental: these run real inference but are not '
                  "validated against Google's outputs on this platform.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            _grid(within(experimental, category), platform),
          ],
          if ([
                for (final task in plannedTasks)
                  if (task.category == category &&
                      !sorted.any((t) => t.title == task.title))
                    task,
              ]
              case final planned when planned.isNotEmpty)
            _plannedGrid(planned),
          if (category == GalleryCategory.vision &&
              within(sorted, category).isEmpty)
            const SliverToBoxAdapter(
              child: _Message(
                icon: Icons.inbox_outlined,
                text: 'No task has a validated runtime on this platform yet.',
              ),
            ),
        ],
      ],
    );
  }

  Widget _header(ThemeData theme, String title) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(title, style: theme.textTheme.titleLarge),
    ),
  );

  Widget _plannedGrid(List<PlannedTask> entries) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 160,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _PlannedCard(task: entries[index]),
    ),
  );

  Widget _grid(List<GalleryTask> entries, TaskPlatform platform) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 160,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) => _TaskCard(
            task: entries[index],
            platform: platform,
            assets: assets,
          ),
        ),
      );

  void _showAbout(BuildContext context) {
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.platform,
    required this.assets,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final GalleryAssets assets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delegates = task
        .capabilitiesFor(platform, assets.officialMacosLandmarkTasks)
        .supportedDelegates;
    return Card.filled(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => switch (task.demo) {
              GalleryDemo.live => LivePage(
                task: task,
                platform: platform,
                officialMacosLandmarkTasks: assets.officialMacosLandmarkTasks,
              ),
              GalleryDemo.segment => SegmentPage(task: task, assets: assets),
              GalleryDemo.text => TextPage(task: task),
              GalleryDemo.audio => AudioPage(task: task),
              // Entries without a screen never reach a tile.
              GalleryDemo.none => throw StateError('${task.id} has no demo'),
            },
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  task.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (task.experimentalReason case final reason?)
                    Tooltip(
                      message: reason,
                      child: Icon(
                        Icons.science_outlined,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  for (final delegate in delegates)
                    Chip(
                      label: Text(
                        delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A task the gallery lists but cannot run yet, with the reason why.
class _PlannedCard extends StatelessWidget {
  const _PlannedCard({required this.task});

  final PlannedTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                task.summary,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.reason,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
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
