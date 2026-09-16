# MagicTouch macOS image editor

From the repository root:

```sh
make example_segmenter
```

Requires Apple Silicon, macOS 14+, Flutter 3.44.8 / Dart 3.12.2 and Xcode.
The first build downloads the optional pinned native runtime. The make target
prepares the unchanged official MagicTouch model and attributed sample images.

Click or draw with **Include** to select an object. **Undo** removes the last
stroke; **Clear** resets the selection. **Open image** accepts JPEG/PNG.
The mask checkbox and threshold affect only the displayed overlay.
Inference runs on CPU; the official macOS GPU stroke graph currently fails.

The default Animals image comes from Google's MediaPipe example assets. The
Portrait sample comes from the attributed face_detection_tflite fixture set.
See [animal attribution](../test/fixtures/interactive_segmentation/README.md)
and [portrait attribution](../test/fixtures/face_detection/README.md).

Only one inference runs at a time; a newer pointer update replaces pending
work. The app disposes obsolete image/mask resources and discards results for
an image or stroke history that has changed.

```sh
flutter test --reporter expanded
flutter build macos --release
```

See [the task guide](../tool/INTERACTIVE_SEGMENTER.md) for consumer configuration,
the stateful Dart API and native release validation.
