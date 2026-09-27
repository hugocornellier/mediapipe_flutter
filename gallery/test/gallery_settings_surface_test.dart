import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_gallery/gallery_settings_drawer.dart';

void main() {
  testWidgets('settings switch stays visible over the panel surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GallerySettingsSurface(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Connections'),
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Connections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
