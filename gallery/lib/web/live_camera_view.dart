import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../live/camera_geometry.dart';
import 'live_camera_controller.dart';

/// Preview and Flutter mesh use identical intrinsic dimensions and mirroring.
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
                final overlay = painter(
                  PreviewTransform.fit(
                    frameSize: frame,
                    rotationDegrees: 0,
                    viewSize: constraints.biggest,
                    mirror: controller.isFrontCamera,
                  ),
                );
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
}
