import 'package:flutter/material.dart';

/// Gives framed desktop pages the shared content background.
class GalleryContentSurface extends StatelessWidget {
  const GalleryContentSurface({
    super.key,
    required this.framed,
    required this.child,
  });

  final bool framed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!framed) return child;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
