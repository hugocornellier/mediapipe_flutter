import 'package:flutter/material.dart';

/// The compact counterpart to the persistent settings panel.
class GallerySettingsDrawer extends StatelessWidget {
  const GallerySettingsDrawer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Drawer(
    shape: const RoundedRectangleBorder(),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    child: GallerySettingsSurface(child: SafeArea(child: child)),
  );
}

/// Chrome and its separator, shared by persistent and compact settings.
class GallerySettingsSurface extends StatelessWidget {
  const GallerySettingsSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: child,
    ),
  );
}
