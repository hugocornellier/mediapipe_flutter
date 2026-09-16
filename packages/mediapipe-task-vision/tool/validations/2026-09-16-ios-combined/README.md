# Combined iOS CPU runtime

Apple Silicon M4 Max, Xcode 26.4, Flutter 3.44.8, iPhone 17 Pro simulator on
iOS 26.4. Source pins and build flags are recorded in the runtime manifests.

`local-consumer.json` records a fresh isolated Flutter consumer of the combined
runtime with SHA-256
`a4fea1f2abddb6d656b043b5471a09a64df1308475422da9800c8f880cd2aa9e`.
All 37 CPU tests passed; 34 macOS-only GPU cases were skipped. The unchanged
Face Detector and Face Landmarker suites cover IMAGE/VIDEO references, pixel
formats, error recovery and queued disposal. A separate normal debug app also
passed inference. The embedded frameworks retain the source library's code and
data after Flutter's packaging and signing changes.

The device slice has SHA-256
`a060f2d1f503e938e4e21432170c1b788563ed7123a6e1a71a9ab3185bae3654`.
Its architecture, IOS platform, exports and system dependencies passed build
checks. Physical-device inference is untested and remains unsupported.

Both use a scoped KleidiAI compiler workaround for the non-streaming SVE crash
observed in the initial simulator build. An isolated eleven-task experimental
run finished without that crash: 107 passed, 56 reference failures, 49 skipped.
Only the two face tasks are declared supported; see UP009 in
[`upstream-issues.md`](../../../../../upstream-issues.md).

Reproduce from the repository root with an installed simulator:

```sh
python3 -B packages/mediapipe-task-vision/tool/build_ios_simulator.py
python3 -B packages/mediapipe-task-vision/tool/test_ios_consumer.py --device <uuid>
python3 -B packages/mediapipe-task-vision/tool/build_ios_simulator.py --sdk iphoneos
python3 -B packages/mediapipe-task-vision/tool/prepare_ios_release.py --simulator-report <report.json>
```

The packager requires a passing report for the exact simulator bytes. Two
independent packaging runs produced identical archive hashes. The release is
prepared locally; the public-download CI path requires its publication.
