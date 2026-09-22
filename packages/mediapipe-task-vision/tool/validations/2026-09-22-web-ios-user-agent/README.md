# iOS Firefox user-agent CPU worker regression, 2026-09-22

The CPU worker omitted the `canvas` option. Under an iOS Firefox user agent,
the bundled runtime's automatic canvas selection called
`document.createElement` inside a module worker, where `document` is absent.
The fix supplies `new OffscreenCanvas(1, 1)` for both delegates and retains
the WebGL 2 capability check for GPU only. No runtime source was changed.

## Red before the fix

[Run 35731757565](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35731757565),
browser job 106758815763, failed on the new assertion at commit
`472034922e4949442a4190003873ded25f1de115`. The only source change from
`ec94349cabbc0a468ebfe78dabb844b5c871d2e0` was the regression test.
The worker still had its baseline blob `15a2ae3fe0b90f4b3cb8cacd0c818c70c0e1aa2c`.

Exact task error:

```text
FaceLandmarkerException(null): Error: document is not defined
```

The assertion and stack are retained in `red-job-excerpt.txt`; the original
artifact reports are `red-report.json` and `red-ios-user-agent-cpu.json`.
Setup, analysis, and both release builds passed before this assertion failed.

## Same test, fixed worker

[Run 35732668310](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35732668310),
browser job 106761921766, passed at commit
`a3f88a10a6f3dc166d24fb99a15bef94621fb007`. Only `worker.js` changed after the
red commit. The regression test and workflow are byte-identical in both runs.

The override used `browser.newContext({userAgent})`; no launch flag was
needed. The test inspects the actual module worker used by the Dart API and
asserts its exact UA, `typeof document === 'undefined'`, and availability of
`OffscreenCanvas`. It briefly holds the task's create message so a failed
creation cannot terminate the worker before inspection, then restores
`postMessage` and releases the unchanged message.

Both artifacts record this UA in the actual task worker:

```text
Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/133.0 Mobile/15E148 Safari/605.1.15
```

The green CPU probe completes construction, inference, lifecycle checks, and
worker disposal. Existing CI coverage also remains green:

| Suite | Checks | Result |
| --- | --- | --- |
| Chromium 153.0.8010.12 CPU, full suite | 18 | Passed, including new UA case and alignment |
| Chromium 153.0.8010.12 GPU, API suite | 7 | Passed |
| Firefox 155.0 CPU, API suite | 7 | Passed |

All three suites report zero maximum absolute error against the same-browser
official JS reference for landmarks, blendshapes, and transformation matrix.
The CPU fake-webcam alignment check reports median 0.001647 and maximum
0.004789 of the preview diagonal, within the existing 0.015 and 0.03 limits.
The mirrored hypothesis is 0.046517. The oracle itself is unchanged.

The scratch run's overall conclusion is failure only because its subsequent
deploy job was rejected by the existing environment policy:
`Branch "ci/web-ios-ua" is not allowed to deploy to github-pages due to environment protection rules.`
Its browser job is successful. No protection rule was changed and no scratch
build was published.

## Limits and remaining hand tests

This is Linux Chromium with an iOS Firefox UA, not WebKit or physical iOS.
The optional Playwright WebKit GPU probe was not run. Safari GPU on an iPhone
remains unproven. This record makes no new physical-device or public-deployment
claim; those need their own retained run or an explicitly labelled visual check.

After deployment, the maintainer should hard reload or open a fresh tab and
test Firefox CPU, Firefox GPU, Safari CPU, and Safari GPU on iOS. For each,
record overlay visibility and alignment, FPS, milliseconds per frame, and any
exact error. The reported Firefox iOS preview letterboxing is a separate
layout issue and is unchanged.

## Retained evidence

- `receipt.json`: source and job IDs, artifact identities, scope, and checks.
- `red-job-excerpt.txt`: failing assertion excerpt from the hosted job, with
  trailing whitespace trimmed.
- `red-report.json`, `red-ios-user-agent-cpu.json`: original red artifact files.
- `green-chromium-cpu-report.json`, `green-ios-user-agent-cpu.json`:
  original green CPU and UA files.
- `green-chromium-gpu-report.json`, `green-firefox-cpu-report.json`:
  original green delegate and browser reports.
- `sha256.json`: byte digests of the retained files.
