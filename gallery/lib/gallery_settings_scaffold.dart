import 'package:flutter/material.dart';

import 'gallery_settings_drawer.dart';
import 'gallery_task_header.dart';
import 'gallery_theme.dart';

/// Keeps wide settings beside the content from top to bottom. Compact pages
/// use the same settings in a right-side drawer.
class GallerySettingsScaffold extends StatelessWidget {
  const GallerySettingsScaffold({
    super.key,
    required this.scaffoldKey,
    required this.framed,
    required this.wide,
    required this.appBar,
    required this.content,
    required this.settings,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool framed;
  final bool wide;
  final AppBar appBar;
  final Widget content;
  final Widget settings;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: framed
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : null,
      appBar: wide ? null : appBar,
      endDrawer: wide ? null : GallerySettingsDrawer(child: settings),
      drawerScrimColor: GalleryTheme.preview.withValues(alpha: 0.54),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: topInset + kToolbarHeight,
                        child: Padding(
                          padding: EdgeInsets.only(top: topInset),
                          child: appBar,
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
                SizedBox(
                  width: gallerySettingsPanelWidth,
                  child: GallerySettingsSurface(
                    child: SafeArea(child: settings),
                  ),
                ),
              ],
            )
          : content,
    );
  }
}
