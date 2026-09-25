import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits for the gallery's grid, then scrolls the tile titled [title] into
/// view and returns its finder.
///
/// The grid sorts tiles by title and builds only those near the screen, so on
/// a short phone a tile further down has no widget until it is scrolled to: a
/// Galaxy S24 shows three tiles, and Live Hand Landmarker is the fourth.
Future<Finder> scrollToGalleryTile(WidgetTester tester, String title) async {
  final grid = find.byType(CustomScrollView);
  for (var i = 0; i < 100 && grid.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  final tile = find.text(title);
  await tester.scrollUntilVisible(
    tile,
    300,
    scrollable: find
        .descendant(of: grid.first, matching: find.byType(Scrollable))
        .first,
  );
  return tile;
}
