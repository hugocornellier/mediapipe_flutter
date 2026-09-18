import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'segment_page.dart';
import 'live_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryApp());
}

/// Assets unpacked to real files, because the native tasks read paths.
final class GalleryAssets {
  const GalleryAssets(this.directory, this.manifest);

  final Directory directory;
  final Map<String, dynamic> manifest;

  Set<String> get bundledTasks =>
      (manifest['tasks'] as List).cast<String>().toSet();

  Set<String> get officialMacosLandmarkTasks =>
      (manifest['official_macos_landmark_tasks'] as List)
          .cast<String>()
          .toSet();

  String path(String name) => '${directory.path}/$name';

  File file(String name) => File(path(name));

  static Future<GalleryAssets> unpack() async {
    final directory = await Directory.systemTemp.createTemp(
      'mediapipe-gallery-',
    );
    final manifest =
        jsonDecode(await rootBundle.loadString('assets/manifest.json'))
            as Map<String, dynamic>;
    for (final group in ['models', 'samples']) {
      final names = group == 'models'
          ? (manifest['models'] as Map).values.cast<String>()
          : (manifest['samples'] as List).cast<String>();
      for (final name in names) {
        final bytes = await rootBundle.load('assets/$group/$name');
        await File('${directory.path}/$name').writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    }
    return GalleryAssets(directory, manifest);
  }
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
    final validated = [
      for (final task in tasks)
        if (!task.isExperimental) task,
    ];
    final experimental = [
      for (final task in tasks)
        if (task.isExperimental) task,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
        if (tasks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: Icons.inbox_outlined,
              text: 'No task has a validated runtime on this platform yet.',
            ),
          )
        else
          _grid(validated, platform),
        if (experimental.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Experimental', style: theme.textTheme.titleMedium),
                  Text(
                    'These run real inference but are not validated against '
                    "Google's outputs on this platform.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _grid(experimental, platform),
        ],
      ],
    );
  }

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
