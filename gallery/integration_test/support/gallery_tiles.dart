import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits for the gallery's grid, then scrolls the tile titled [title] into
/// view and returns its finder.
///
/// The grid sorts tiles by title and builds only those near the screen, so on
/// a short phone a tile further down has no widget until it is scrolled to: a
/// Galaxy S24 shows three tiles, and Hand Landmarker is the fourth.
Future<Finder> scrollToGalleryTile(WidgetTester tester, String title) async {
  final grid = find.byType(CustomScrollView);
  // On a cold Windows runner unpacking assets can outlast the first few
  // frames. Wait for the scrollable child too, so scrolling never receives a
  // finder for a gallery that has not finished building.
  final scrollable = find.descendant(
    of: grid,
    matching: find.byType(Scrollable),
  );
  for (
    var i = 0;
    i < 600 && (grid.evaluate().isEmpty || scrollable.evaluate().isEmpty);
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  expect(grid, findsOneWidget, reason: 'Home gallery did not load');
  expect(scrollable, findsWidgets, reason: 'Home gallery is not scrollable');
  // The wide layout also shows this name in the sidebar. Select the Home
  // grid's tile so the finder remains unique on desktop.
  final tile = find.descendant(of: grid.first, matching: find.text(title));
  await tester.scrollUntilVisible(tile, 300, scrollable: scrollable.first);
  return tile;
}
