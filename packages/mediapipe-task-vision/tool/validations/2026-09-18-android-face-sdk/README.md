Two physical Pixel 7 (`panther`) / Android API 33 executions passed on
2026-09-18 using Google's released Android FaceLandmarker SDK 1.0.0.

- Initial run: three tests passed, matrix `matrix-3e6omhpdcemst`.
- Final run: four tests passed, matrix `matrix-1ypt8roxiisio`, including the
  ordinary gallery's Live Face Mesh tile and CPU → GPU → CPU buttons.

Both CPU and GPU produce 478 finite landmarks, 52 blendshapes and a valid
column-major 4×4 transform for the known bundled face. Padded RGB/RGBA/BGRA
inputs preserve same-delegate coordinates. VIDEO tests cover queued frames,
timestamps, repeated faces, blank frames, recovery, all four rotations, invalid
models and disposal. The final run includes explicit direct-model-buffer
lifetime retention in the Java adapter.

Front and back camera capture each processed at least twenty frames on both
delegates. Camera frames were 720×480, with front rotation 270° and back 90°.
The rack cameras saw no faces. This validates the live capture/conversion/task
pipeline; the bundled photo validates nonempty face inference. Visual mesh
alignment over a person and device orientation UI changes remain untested.

`summary.json` retains diagnostic events, original raw-log hashes, model/SDK
hashes and successful matrix outcomes. APK receipts identify the exact uploaded
debug apps; the final receipt also hashes adapter/test sources. Application
logs retain only the tested app's process. Complete logcat and videos remain in
the Test Lab result bucket under `mediapipe-face-20260918-a1-11177c7` and
`mediapipe-face-20260918-a2-11177c7`.

The ordinary gallery release APK also builds successfully with the Android SDK;
it was not the instrumented Test Lab APK. Debug timings are diagnostic and
provide no release performance claim or broad Android device coverage.

Local checks passed: sixteen camera conversion/geometry tests, three Android SDK
hook tests, sixteen existing iOS/runtime hook tests, and twenty-three macOS CPU/GPU
FaceLandmarker reference/lifecycle tests. Analysis and source whitespace checks
pass. Existing staged changes were preserved.

Reproduction: [Android Test Lab guide](../../../../../gallery/tool/ANDROID_FACE_TESTLAB.md).
Final [Firebase result](https://console.firebase.google.com/project/flutter-litert/testlab/histories/bh.6fbb7acd7654206e/matrices/8562909720019103204).
