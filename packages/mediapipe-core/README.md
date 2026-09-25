# MediaPipe Core for Flutter

`mediapipe_flutter_core` is part of the public
[mediapipe_flutter](../../README.md) development fork. It owns the optional,
verified MediaPipe runtime shared by the text and audio tasks: Google's 1.0.1
library on macOS 14+ arm64 (also serving MagicTouch and the newer text tasks),
on Linux x64 (1.0.1) and Windows x64 (1.0.0) the official wheel library the
vision package pins, which the vision hook then shares instead of bundling a
second copy, and on iOS the vision package's adapter over Google's 1.0.1 iOS
SDK, which implements every task in one framework. Apps enable it with
`hooks.user_defines.mediapipe_flutter_core.tasks_runtime: true`.
Its inherited container types also remain available for compatibility.


A Flutter plugin to use the MediaPipe Core API, which enables multiple Mediapipe tasks.

To learn more about MediaPipe, please visit the [MediaPipe website](https://developers.google.com/mediapipe)

## Getting Started

To get started with MediaPipe, please [see the documentation](https://developers.google.com/mediapipe/solutions/guide).

<!-- ASPIRATIONAL
## Usage

To use this plugin, please visit the [Core Usage documentation](https://github.com/hugocornellier/mediapipe_flutter#Usage)
-->

## Issues and feedback

Please file mediapipe_flutter specific issues, bugs, or feature requests in our [issue tracker](https://github.com/hugocornellier/mediapipe_flutter/issues/new).

Issues that are specific to Flutter can be filed in the [Flutter issue tracker](https://github.com/flutter/flutter/issues/new).

To contribute a change to this plugin,
please review our [contribution guide](https://github.com/hugocornellier/mediapipe_flutter/blob/main/CONTRIBUTING.md)
and open a [pull request](https://github.com/hugocornellier/mediapipe_flutter/pulls).
