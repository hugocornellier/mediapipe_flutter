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
import 'gallery_content_surface.dart';
import 'gallery_theme.dart';
import 'gallery_assets_io.dart'
    if (dart.library.js_interop) 'web/gallery_assets.dart';
export 'gallery_assets_io.dart'
    if (dart.library.js_interop) 'web/gallery_assets.dart';

SemanticsHandle? _webSemantics;

const _sidebarWidth = 288.0;

// Keep page navigation close to an immediate web page change on every target.
const _pageFade = _QuickFadePageTransitionsBuilder();
final _pageTransitions = PageTransitionsTheme(
  builders: {for (final platform in TargetPlatform.values) platform: _pageFade},
);

class _QuickFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _QuickFadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 90);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

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
    theme: GalleryTheme.data(
      Brightness.light,
    ).copyWith(pageTransitionsTheme: _pageTransitions),
    darkTheme: GalleryTheme.data(
      Brightness.dark,
    ).copyWith(pageTransitionsTheme: _pageTransitions),
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
        return _GalleryShell(assets: assets, platform: platform, tasks: tasks);
      },
    ),
  );
}

/// Keeps navigation in view on wide screens and in a modal drawer on phones.
class _GalleryShell extends StatefulWidget {
  const _GalleryShell({
    required this.assets,
    required this.platform,
    required this.tasks,
  });

  final GalleryAssets assets;
  final TaskPlatform platform;
  final List<GalleryTask> tasks;

  @override
  State<_GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<_GalleryShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  GalleryTask? _selectedTask;

  void _select(GalleryTask? task) {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    if (_selectedTask?.id != task?.id) setState(() => _selectedTask = task);
  }

  Widget _page(bool wide) {
    final task = _selectedTask;
    final openMenu = wide
        ? null
        : () => _scaffoldKey.currentState?.openDrawer();
    if (task == null) {
      return _Gallery(
        assets: widget.assets,
        platform: widget.platform,
        tasks: widget.tasks,
        onTaskSelected: _select,
        onOpenMenu: openMenu,
        framed: wide,
      );
    }
    return switch (task.demo) {
      GalleryDemo.live => LivePage(
        task: task,
        platform: widget.platform,
        officialMacosLandmarkTasks: widget.assets.officialMacosLandmarkTasks,
        onOpenMenu: openMenu,
        framed: wide,
      ),
      GalleryDemo.segment => SegmentPage(
        task: task,
        assets: widget.assets,
        onOpenMenu: openMenu,
        framed: wide,
      ),
      GalleryDemo.text => TextPage(
        task: task,
        onOpenMenu: openMenu,
        framed: wide,
      ),
      GalleryDemo.audio => AudioPage(
        task: task,
        onOpenMenu: openMenu,
        framed: wide,
      ),
      GalleryDemo.none => throw StateError('${task.id} has no demo'),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final sidebar = _NavigationSidebar(
        tasks: widget.tasks,
        selectedTask: _selectedTask,
        onSelect: _select,
      );
      final contentWidth = constraints.maxWidth - (wide ? _sidebarWidth : 0);
      final content = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(size: Size(contentWidth, MediaQuery.sizeOf(context).height)),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 90),
          // Drop the outgoing task immediately so its camera and worker can
          // close before another task starts. Only the new page fades in.
          layoutBuilder: (currentChild, previousChildren) =>
              currentChild ?? const SizedBox.shrink(),
          child: KeyedSubtree(
            key: ValueKey(_selectedTask?.id ?? 'home'),
            child: _page(wide),
          ),
        ),
      );
      final theme = Theme.of(context);
      final page = Theme(
        data: wide
            ? theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                ),
              )
            : theme,
        child: content,
      );
      return Scaffold(
        key: _scaffoldKey,
        drawer: wide
            ? null
            : Drawer(shape: const RoundedRectangleBorder(), child: sidebar),
        drawerScrimColor: GalleryTheme.preview.withValues(alpha: 0.54),
        body: Row(
          children: [
            if (wide) SizedBox(width: _sidebarWidth, child: sidebar),
            Expanded(key: const ValueKey('gallery-content'), child: page),
          ],
        ),
      );
    },
  );
}

class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.tasks,
    required this.selectedTask,
    required this.onSelect,
  });

  final List<GalleryTask> tasks;
  final GalleryTask? selectedTask;
  final ValueChanged<GalleryTask?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...tasks]..sort((a, b) => a.title.compareTo(b.title));
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _item(
                      context,
                      'Home',
                      selectedTask == null,
                      () => onSelect(null),
                    ),
                    for (final category in GalleryCategory.values)
                      if (sorted.any((task) => task.category == category)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
                          child: Text(
                            category.title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        for (final task in sorted)
                          if (task.category == category)
                            _item(
                              context,
                              task.title,
                              selectedTask?.id == task.id,
                              () => onSelect(task),
                            ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String title,
    bool selected,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        link: true,
        label: title,
        selected: selected,
        onTap: onTap,
        child: ExcludeSemantics(
          child: ListTile(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: selected,
            selectedColor: scheme.onPrimary,
            selectedTileColor: scheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            dense: true,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// Wider windows keep the catalog at a readable width, centred.
const _maxContentWidth = 1200.0;

class _Gallery extends StatefulWidget {
  const _Gallery({
    required this.assets,
    required this.platform,
    required this.tasks,
    required this.onTaskSelected,
    required this.onOpenMenu,
    required this.framed,
  });

  final GalleryAssets assets;
  final TaskPlatform platform;
  final List<GalleryTask> tasks;
  final ValueChanged<GalleryTask> onTaskSelected;
  final VoidCallback? onOpenMenu;
  final bool framed;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
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
    return Scaffold(
      backgroundColor: widget.framed
          ? theme.colorScheme.surfaceContainerLow
          : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Open navigation',
                onPressed: widget.onOpenMenu,
              ),
        flexibleSpace: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: kToolbarHeight,
            child: Transform.translate(
              offset: Offset(widget.framed ? -_sidebarWidth / 2 : 0, 0),
              child: Center(
                child: Text(
                  'MediaPipe Gallery',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
          ),
        ),
      ),
      body: GalleryContentSurface(
        framed: widget.framed,
        child: CustomScrollView(
          slivers: [
            if (compact)
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
            for (final category in shown) ...[
              _header(theme, category, inset),
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
              if (plannedIn(category) case final planned
                  when planned.isNotEmpty)
                _plannedGrid(planned, inset, compact),
            ],
            if (within(sorted, GalleryCategory.vision).isEmpty)
              const SliverToBoxAdapter(
                child: _Message(
                  icon: Icons.inbox_outlined,
                  text: 'No task has a validated runtime on this platform yet.',
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, GalleryCategory category, double inset) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, 32, inset, 14),
        sliver: SliverToBoxAdapter(
          child: Text(
            category.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  SliverGridDelegate _layout(bool compact) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 640 : 380,
        mainAxisExtent: compact ? 92 : 120,
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
            onSelected: widget.onTaskSelected,
          ),
        ),
      );
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

/// CPU or GPU, as a small pill; GPU uses the shared gallery accent.
class _DelegateBadge extends StatelessWidget {
  const _DelegateBadge({required this.gpu});

  final bool gpu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: gpu
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        gpu ? 'GPU' : 'CPU',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: gpu
              ? theme.colorScheme.onPrimaryContainer
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
    required this.onSelected,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final GalleryAssets assets;
  final bool compact;
  final ValueChanged<GalleryTask> onSelected;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final delegates = task
        .capabilitiesFor(
          widget.platform,
          widget.assets.officialMacosLandmarkTasks,
        )
        .supportedDelegates;
    final badges = [
      if (task.experimentalReason case final reason?)
        Tooltip(
          message: reason,
          child: Text(
            'Exp',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        ),
      // Every task runs on the CPU; a phone row names only the GPU.
      for (final delegate in delegates)
        if (!widget.compact || delegate == VisionDelegate.gpu)
          _DelegateBadge(gpu: delegate == VisionDelegate.gpu),
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
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          onTap: () => widget.onSelected(task),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // The badges follow the text in both layouts, so a screen reader
            // announces the title first.
            child: widget.compact
                ? Row(
                    children: [
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 4),
                      summary,
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: badges,
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
    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(color: muted),
    );
    final reason = Text(
      task.reason,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: muted),
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
                  title,
                  const SizedBox(height: 4),
                  Text(
                    task.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const Spacer(),
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
