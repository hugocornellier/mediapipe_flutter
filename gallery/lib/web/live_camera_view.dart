import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:web/web.dart' as web;
import '../live/camera_geometry.dart';
import '../live/face_overlay.dart';
import 'live_camera_controller.dart';
import 'test_hooks.dart';

/// Preview and Flutter landmarks use identical intrinsic dimensions and mirroring.
class LiveCameraView extends StatelessWidget {
  const LiveCameraView({
    super.key,
    required this.controller,
    required this.painter,
    required this.placeholder,
  });
  final LiveCameraController<Object?> controller;
  final CustomPainter? Function(PreviewTransform transform) painter;
  final Widget placeholder;
  @override
  Widget build(BuildContext context) {
    final frame = controller.frameSize;
    // Keep the video attached while a running task changes delegate/device.
    // Removing its platform view during stream replacement can prevent Chrome
    // from delivering requestVideoFrameCallback on the restarted stream.
    if (frame == null) return Center(child: placeholder);
    return Center(
      child: AspectRatio(
        aspectRatio: frame.width / frame.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HtmlElementView.fromTagName(
              tagName: 'div',
              onElementCreated: (element) {
                // The video is owned by the controller and reused across restarts.
                final container = element as web.HTMLElement;
                container.style
                  ..width = '100%'
                  ..height = '100%'
                  ..pointerEvents = 'none';
                container.append(controller.video);
              },
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final transform = PreviewTransform.fit(
                  frameSize: frame,
                  rotationDegrees: 0,
                  viewSize: constraints.biggest,
                  mirror: controller.isFrontCamera,
                );
                if (testHooks) _publishProbes(context, transform);
                final overlay = painter(transform);
                return overlay == null
                    ? const SizedBox.shrink()
                    : CustomPaint(painter: overlay);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Records on the video element where the overlay draws
  /// [faceAlignmentProbes], for the browser suite's alignment oracle
  /// (`tool/browser/test_browser.mjs`).
  ///
  /// Uses the painter's own [transform] and reads the overlay's place on the
  /// page after layout; logical pixels are CSS pixels on web. The probes and
  /// the fitted frame are relative to that overlay box.
  void _publishProbes(BuildContext context, PreviewTransform transform) {
    final video = controller.video;
    final result = controller.result;
    if (result is! FaceLandmarkerResult || result.faceLandmarks.isEmpty) {
      video.removeAttribute('data-probes');
      return;
    }
    final face = result.faceLandmarks.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.mounted ? context.findRenderObject() : null;
      if (box is! RenderBox || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      final fitted = transform.uprightSize * transform.scale;
      final probes = <String, List<double>>{};
      for (final index in faceAlignmentProbes) {
        final point = transform.map(face[index].x, face[index].y);
        probes['$index'] = [point.dx, point.dy];
      }
      video
        ..setAttribute(
          'data-overlay-box',
          jsonEncode([origin.dx, origin.dy, box.size.width, box.size.height]),
        )
        ..setAttribute(
          'data-frame-box',
          jsonEncode([
            transform.offsetX,
            transform.offsetY,
            fitted.width,
            fitted.height,
          ]),
        )
        ..setAttribute('data-mirror', '${transform.mirror}')
        ..setAttribute('data-rotation', '${transform.quarterTurns * 90}')
        ..setAttribute('data-probes', jsonEncode(probes));
    });
  }
}
