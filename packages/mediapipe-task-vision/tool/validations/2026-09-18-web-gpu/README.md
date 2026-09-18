# Web GPU FaceLandmarker validation

The web adapter now passes the explicitly selected CPU/GPU delegate to Google's
unmodified Tasks Vision 1.0.1 runtime. GPU owns a worker OffscreenCanvas/WebGL 2
context; initialization failures propagate and never select the CPU delegate.

Local release Chromium GPU IMAGE/VIDEO tests passed, including padded pixels,
rotations, queued frames and disposal. All 478 XYZ landmarks, 52 blendshape
scores and 16 matrix values matched the same-browser official JavaScript GPU
reference exactly (maximum absolute error zero). The API report is retained here.

System Chrome also passed two real MacBook camera GPU sessions at 640x480,
with 20 and 21 processed frames and a visible face producing 478 landmarks in
both sessions. Stop/restart released workers and tracks. Device identifiers are
redacted from the retained report; no physical-camera images were saved.

The live-camera report uses a file-backed webcam and confirms face/blank/face
recovery, CPU → GPU → CPU task switching, preview geometry and cleanup, alongside
permission/device/worker failures. Keeping the video platform view attached
during a running task switch fixes Chrome's restarted-stream frame callbacks.

The web workflow repeats these tests on hosted Linux using SwiftShader software
WebGL for Chromium. This verifies the GPU delegate path, not physical GPU
performance. Firefox retains its CPU reference checks. Pages publishes the
tested artifact and repeats the live delegate-switch test on the public URL.
Google's FaceBlendshapesGraph uses XNNPACK even when GPU is selected; this is the
official task's behavior, not an adapter fallback.
