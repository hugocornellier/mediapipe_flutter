import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../catalog.dart';
import 'components.dart';
import 'design.dart';

/// The design's top bar, shown while the sidebar is hidden: the menu, the
/// page's title, and the settings button on phones.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.onOpenMenu,
    this.onOpenSettings,
  });

  final String title;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: onOpenMenu == null
                    ? null
                    : OutlineButton(
                        icon: LucideIcons.menu,
                        tooltip: 'Open navigation',
                        onPressed: onOpenMenu,
                        bordered: false,
                      ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: Sizes.md,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: onOpenSettings == null
                    ? null
                    : OutlineButton(
                        icon: LucideIcons.settings2,
                        tooltip: 'Settings',
                        onPressed: onOpenSettings,
                        bordered: false,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The settings column: CONFIGURATION / Settings over its sections.
class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.child, this.onClose});

  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Configuration'),
                  const SizedBox(height: 7),
                  Text(
                    'Settings',
                    style: TextStyle(color: c.text, fontSize: 20),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              OutlineButton(
                icon: LucideIcons.x,
                tooltip: 'Close settings',
                onPressed: onClose,
              ),
          ],
        ),
        const SizedBox(height: 34),
        child,
      ],
    );
  }
}

/// A task page: its heading and body scroll in the middle, centred at the
/// design's width, with settings beside them or, on phones, in a bottom
/// sheet the top bar opens.
class TaskWorkspace extends StatelessWidget {
  const TaskWorkspace({
    super.key,
    required this.title,
    required this.onOpenMenu,
    required this.settings,
    required this.children,
  });

  final String title;

  /// Opens the sidebar; null while it is in view.
  final VoidCallback? onOpenMenu;

  /// Settings sections, or null for a page without settings.
  final Widget? settings;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Sizes.compact;
    final panel = !phone && settings != null;
    final body = GalleryPageBody(children: children);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          if (onOpenMenu != null || phone)
            Builder(
              builder: (context) => TopBar(
                title: title,
                onOpenMenu: onOpenMenu,
                onOpenSettings: phone && settings != null
                    ? () => showSettingsSheet(context, settings!)
                    : null,
              ),
            ),
          // The body keeps its place in the row when the panel comes and
          // goes, so crossing the phone breakpoint relays out the page
          // instead of rebuilding it and its camera view.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: body),
                if (panel)
                  Container(
                    width: Sizes.settings,
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(left: BorderSide(color: c.line)),
                    ),
                    child: SafeArea(
                      left: false,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SettingsColumn(child: settings!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [settings] as the design's phone bottom sheet.
Future<void> showSettingsSheet(BuildContext context, Widget settings) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      builder: (context) => SettingsColumn(
        onClose: () => Navigator.of(context).pop(),
        child: settings,
      ),
    );

/// A page's scrolling body at the design's width and padding.
class GalleryPageBody extends StatelessWidget {
  const GalleryPageBody({
    super.key,
    required this.children,
    this.maxWidth = Sizes.content,
  });

  final List<Widget> children;

  /// The widest the content grows, centred in wider windows.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Sizes.compact;
    // The window's own width, since the shell narrows this page's by the
    // sidebar's: below the wide breakpoint the top bar takes the space.
    final view = View.of(context);
    final tablet = view.physicalSize.width / view.devicePixelRatio < Sizes.wide;
    final padding = phone
        ? const EdgeInsets.fromLTRB(16, 28, 16, 52)
        : EdgeInsets.fromLTRB(44, tablet ? 36 : 48, 44, 72);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Help button's dialog: what the task does, the model it runs, and
/// Google's guide to it.
Future<void> showTaskHelp(BuildContext context, GalleryTask task) {
  final c = GalleryColors.of(context);
  final family = task.category.title.toLowerCase();
  final id = task.runtimeId == 'interactive_segmenter_legacy'
      ? 'interactive_segmenter'
      : task.runtimeId;
  final guide = 'https://ai.google.dev/edge/mediapipe/solutions/$family/$id';
  final label = TextStyle(color: c.muted, fontSize: Sizes.sm);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(task.title, style: TextStyle(color: c.text, fontSize: 20)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.summary,
              style: TextStyle(color: c.text, fontSize: Sizes.md, height: 1.5),
            ),
            const SizedBox(height: 18),
            const Eyebrow('Model'),
            const SizedBox(height: 6),
            Text(task.model, style: label),
            const SizedBox(height: 18),
            const Eyebrow('Guide'),
            const SizedBox(height: 6),
            SelectableText(
              guide,
              style: TextStyle(color: c.teal, fontSize: Sizes.sm),
            ),
            const SizedBox(height: 18),
            Text(
              'Settings, the model and the delegate are in the settings '
              'panel. Every change rebuilds the task with it.',
              style: label.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        PrimaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
