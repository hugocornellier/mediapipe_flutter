# Asset hosting

Planned, not started: every package download depends on one third-party host
and gives up after one failed attempt per URL. Found on 2026-10-15, on `main`
at `ed23dcb`, after a jsDelivr outage failed three CI jobs on PR #88. Paths
are from the repository root. Check a finding again before building on it.

## Goal

No single host's outage breaks an app, a build or a CI run:

1. **Browsers load Google's runtime from the app's own origin.** Each family
   package ships the files its worker loads, and other hosts are only
   fallbacks.
2. **Every pin can have fallback hosts.** Each host must serve the pinned
   bytes, which are checked before use, so adding a host never weakens
   anything.
3. **Every download retries.** A few attempts per host, only for transient
   failures, with exponential backoff and jitter, resuming partial native
   downloads, then the next host.
4. **Google's official hosting fits in when it exists.** Google plans a
   Google Cloud Storage bucket for its libraries; it becomes the primary host
   and today's hosts become its fallbacks.

## What happened

On 2026-10-15 jsDelivr's cache misses failed: after 54 to 91 s they returned
502 or 503 with `x-cache: MISS`, `cf-cache-status: BYPASS` and no
`Access-Control-Allow-Origin`, so browsers reported only "Failed to fetch".
Files already in jsDelivr's cache still loaded. On PR #88 that failed:

- the Firefox journey: HTTP 503 for
  `@mediapipe/tasks-audio@1.0.1/wasm/audio_wasm_module_internal.wasm`;
- the Chromium text and audio run, which saw no audio runtime request;
- Retrieval web on Chromium (macos-15), twice: `TaskException: Error: Failed
  to fetch`;
- the coverage gate, which then lacked `universal_embedder` and
  `semantic_retriever` on web/gpu.

During the outage unpkg served the same retrieval WASM with the pinned
SHA-384. Reruns passed after jsDelivr recovered around 14:25 UTC. CI already
self-hosts the runtime for its direct comparisons with Google's JavaScript and
for one text and audio run (`web.yaml`, `dart run mediapipe_core:web_runtime`),
but the gallery's own tasks load from jsDelivr, as any app's do by default.

## Today

| Asset | Fetched by | From | Fallback today |
| --- | --- | --- | --- |
| Browser runtime: bundle and WASM | each family's `assets/worker.js`, through core's `assets/verified_runtime.js` | `cdn.jsdelivr.net` (`MediaPipeWebRuntime.defaultBaseUrl`) | none: one `baseUrl` |
| Native per-family libraries | build hooks, through `downloadVerified` | this project's GitHub release `per-family-v1.1.1-dev.20261009` (`familyRuntimeBaseUrl`) | none |
| Decision Maker's Windows library, reference wheels | build hook, tools | `files.pythonhosted.org` | none |
| Models, native | `ModelStore`, `bundle_models`, through `downloadVerified` | `storage.googleapis.com`, `huggingface.co` | `DownloadAsset.mirrors`, but no pin names one |
| Models, web | `ModelStore` (`model_store_web.dart`), workers given a `modelPath` | the same | the same |
| npm tarball for the `web_runtime` command | `web_runtime_host.dart` | `registry.npmjs.org` | none |

What already helps:

- `dart run mediapipe_core:web_runtime web/mediapipe` and
  `MediaPipeWebRuntime.baseUrl = 'mediapipe/'` self-host the browser runtime.
  It is opt-in, takes a step after every runtime bump, and copies all seven
  files `runtime.json` lists, though a browser loads three of them (below).
- `DownloadAsset.mirrors` are tried in order. The `asset_source` user define,
  `ModelStore(source: ...)` and `MEDIAPIPE_ASSET_SOURCE` replace every host
  with one SHA-named directory or URL, deliberately with no fallback, for
  offline builds. `tool/mirror_runtime_assets.py` lists every pin with a
  release asset name (`<sha256>-<file>`) and its license.
- Every file is checked against its pin: SHA-256 for native downloads,
  SHA-384 for browser files.

What is missing: `downloadVerified` makes one attempt per URL, with a 60 s
timeout on the response and on each gap in the stream, and throws away a
partial file. The browser side (`verified_runtime.js`, `model_store_web.dart`,
the workers' `fetch(modelPath)`) makes one `fetch` per file. Nothing in
`packages/*/lib` or the workers retries.

## Findings that shape the design

**A browser loads three files per family.** The loader calls
`FilesetResolver.for<Family>Tasks('wasm', true)`. With `true` (use a module),
Google's resolver skips its SIMD check and always returns the module build.
From `text_bundle.mjs` 1.0.1, read on 2026-10-15:

```js
async function Wo(t){if(t)return!0; /* ...SIMD probe... */}
async function Ho(t,e,r){return{wasmLoaderPath:`${e}/${t}_${r=`wasm${r?"_module":""}${await Wo(r)?"":"_nosimd"}_internal`}.js`,wasmBinaryPath:`${e}/${t}_${r}.wasm`}}
```

So the files are `<family>_bundle.mjs` and
`wasm/<family>_wasm_module_internal.{js,wasm}`. The SIMD and no-SIMD builds
in `runtime.json` are never loaded, and `verified_runtime.js`'s comment that
the resolver "only picks the variant this browser supports (SIMD or not)" is
wrong for this call.

**Sizes.** The three files: vision 12 MB, text 7, audio 6, retrieval 21,
decision 18, so 64 MB for all five. `gzip -9` takes retrieval's 21.5 MB WASM
to 6.4 MB (30%), so about 19 MB compressed for all five. All seven files are
three times that (npm unpacked: vision 37 MB, text 22, audio 21, retrieval 66,
decision 54). pub.dev refuses a package over 100 MB. The repository's pack is
73 MB. No browser pin has changed since it was added (vision, text and audio
1.0.1 on 2026-09-30, decision 1.1.0 on 2026-10-08, retrieval 1.1.0 on
2026-10-09), so committed files would grow the history only when Google
publishes a new version.

**Cross-origin rules decide which hosts a browser can use.** A worker
fetching from another origin needs `Access-Control-Allow-Origin` on the
response.

| Host | CORS | Usable by browsers |
| --- | --- | --- |
| The app's own origin | not needed | yes |
| jsDelivr, unpkg | `*` | yes |
| GitHub Pages | `*` | yes, but a site is capped at 1 GB |
| GitHub Release downloads | none (checked on the 302 and the final 200) | no |
| A Google Cloud Storage bucket | only if its owner sets a CORS rule | ask Google |

The host's `Content-Type` does not matter: the loader wraps the checked bytes
in blob URLs with the right MIME type itself.

**Range requests work on every native host.** `curl -r 0-99` got HTTP 206
with 100 bytes from the GitHub release (through
`release-assets.githubusercontent.com`), `storage.googleapis.com` and
`huggingface.co` on 2026-10-15, so a dropped native download can resume.

**Licenses allow it.** Google's npm runtimes are Apache-2.0 (`package.json`'s
`license`; the tarball has no LICENSE file), so the packages may ship them
with the license text, which core already carries in
`packages/mediapipe-core/third_party/` for the native libraries. Models need
a check per model before anyone mirrors them: `mirror_runtime_assets.py`
marks the Gemma-based ones `Gemma Terms`, whose notice must travel with every
copy.

**A shared CDN no longer saves downloads.** Browsers partition their HTTP
cache by top-level site (Chrome since 86, Firefox since 85, Safari earlier),
so a copy another site loaded from jsDelivr is not reused. Serving from the
app's origin loses no caching.

## Plan

### 1. Ship the browser runtime in each family package

Each family declares its three files as web-only assets, next to the ones it
already has (text shown):

```yaml
flutter:
  assets:
    - path: assets/worker.js
      platforms: [web]
    - path: assets/runtime.json
      platforms: [web]
    - path: assets/runtime/text_bundle.mjs
      platforms: [web]
    - path: assets/runtime/wasm/text_wasm_module_internal.js
      platforms: [web]
    - path: assets/runtime/wasm/text_wasm_module_internal.wasm
      platforms: [web]
```

Flutter serves them at `assets/packages/mediapipe_text/assets/runtime/`, the
worker's own folder plus `runtime/`, so the worker finds them without any app
setting. Native builds leave them out.

A command (core's `web_runtime_host.dart` already downloads the npm tarball
and checks its integrity) writes the files on a runtime bump, and a test
checks each committed file against `runtime.json`'s SHA-384, so a bump cannot
leave stale files behind. `runtime.json` can then list only the three files.

### 2. Try hosts in order in the browser

`verified_runtime.js` takes a list of roots instead of one. Every root must
serve the pinned bytes; a root that fails, after retries, or serves other
bytes passes the file to the next one:

```js
// The copy this package ships comes first; npm-style roots follow.
const roots = [
  new URL('runtime/', import.meta.url),
  ...npmRoots.map(root => new URL(`${pin.package}@${pin.version}/`, root)),
];

async function verified(name) {
  const failures = [];
  for (const root of roots) {
    try {
      const bytes = await fetchWithRetries(new URL(name, root));
      if (await sha384(bytes) === pin.sha384[name]) return bytes;
      failures.push(`${root}: SHA-384 mismatch`);
    } catch (error) {
      failures.push(`${root}: ${error.message}`);
    }
  }
  throw new Error(`MediaPipe runtime ${name}: ${failures.join('; ')}`);
}
```

The Dart setting becomes a list. One possible shape (the public API, so
`tool/api_parity`'s snapshots change with it):

```dart
abstract final class MediaPipeWebRuntime {
  /// npm-style roots tried in order after the copy each family package ships.
  static List<String> fallbackUrls = const [
    'https://cdn.jsdelivr.net/npm/',
    'https://unpkg.com/',
  ];

  /// When set, tried before the shipped copy, as `baseUrl` is today.
  static String? baseUrl;
}
```

An app that sets `baseUrl = 'mediapipe/'` keeps working. An app with a strict
Content Security Policy sets `fallbackUrls = const []` and loads only from its
own origin. When Google's bucket exists and allows cross-origin requests, it
goes before jsDelivr.

### 3. Fallback hosts for native downloads

Native downloads need no CORS, so a GitHub release works as a host there.
When Google publishes its bucket:

```dart
DownloadAsset get asset => DownloadAsset(
  url: '$officialRuntimeBaseUrl/$fileName', // Google's bucket
  sha256: sha256,
  mirrors: ['$familyRuntimeBaseUrl/$sha256-$fileName'], // this project's release
);
```

Until then, the GitHub release stays the primary host. Models keep Google's
or Hugging Face's URL first and can name a mirror release holding
`<sha256>-<file>`, the names `mirror_runtime_assets.py` already proposes,
once each model's license is checked. `asset_source` stays exclusive:
offline builds must never reach the internet.

### 4. Retries, backoff and resume

The same rules everywhere:

- **Attempts:** up to 3 per host, then the next host.
- **Retry only what can pass on retry:** connection errors, timeouts, and HTTP
  408, 429, 500, 502, 503 and 504. Move to the next host at once on any
  other status (403, 404, 410) or on a digest mismatch.
- **Delay:** exponential with full jitter, a random wait between 0 and
  `min(30 s, 1 s × 2^attempt)`, or the response's `Retry-After` when it
  names one, capped at 30 s.
- **Resume (native only):** after a dropped connection, ask for the rest with
  `Range: bytes=<received>-` and `If-Range` set to the first response's
  `ETag`. Append on 206; start over on 200. The final SHA-256 check guards
  either way.
- **Timeouts:** keep 60 s for the response and for each gap in the stream,
  with no limit on the whole download, since large models are slow but
  alive. In browsers, `AbortSignal.timeout(60_000)` per attempt.
- **Report every attempt** in `DownloadException`, which already lists each
  failed location.

In `downloadVerified`, the single `connection.send` becomes a loop like this
(sketch):

```dart
const _transientStatus = {408, 429, 500, 502, 503, 504};

Future<void> _download(http.Client client, Uri uri, File partial) async {
  String? validator;
  for (var attempt = 0; ; attempt++) {
    final received = await partial.exists() ? await partial.length() : 0;
    final request = http.Request('GET', uri);
    if (received > 0 && validator != null) {
      request.headers['range'] = 'bytes=$received-';
      request.headers['if-range'] = validator;
    }
    final http.StreamedResponse response;
    try {
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200 || response.statusCode == 206) {
        validator ??= response.headers['etag'];
        final sink = partial.openWrite(
          mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
        );
        try {
          await sink.addStream(
            response.stream.timeout(const Duration(seconds: 60)),
          );
        } finally {
          await sink.close();
        }
        return;
      }
      await response.stream.drain<void>();
    } on Exception {
      // Connection errors and timeouts, including a drop mid-stream.
      if (attempt == 2) rethrow;
      await Future<void>.delayed(_backoff(attempt));
      continue;
    }
    if (!_transientStatus.contains(response.statusCode) || attempt == 2) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    await Future<void>.delayed(
      _retryAfter(response.headers['retry-after']) ?? _backoff(attempt),
    );
  }
}

Duration _backoff(int attempt) => Duration(
  milliseconds: Random().nextInt(min(30000, 1000 << attempt) + 1),
);

// Only the seconds form; an HTTP date falls back to the backoff.
Duration? _retryAfter(String? value) => switch (int.tryParse(value ?? '')) {
  final seconds? => Duration(seconds: min(seconds, 30)),
  null => null,
};
```

`model_store_web.dart`'s `_fetch`, the workers' `fetch(modelPath)` and
`verified_runtime.js` share one browser helper with the same rules, without
resume. Tests drive it with `package:http/testing`'s `MockClient` (for
example 503, 503, then 200; or a stream that drops halfway, then a 206) and
an injected delay, so they never wait.

## Decisions to take

- **Commit the runtime files or fetch them at publish time.** Committed
  (recommended): a clone, a git dependency, the gallery and CI all work with
  no extra step, at about 19 MB of compressed history for all five families
  now and for each later bump of all five. Fetched at publish (git-ignored, kept by a `.pubignore`): git
  stays small, but a git or path dependency, including the gallery, needs a
  fetch step or falls back to the CDN.
- **What Google's bucket allows.** Its URL and layout, and whether it sends
  `Access-Control-Allow-Origin` so browsers can use it, not only build hooks.
- **The `web_runtime` command's future.** With the runtime inside the
  packages it is only for apps that serve it elsewhere; keep it, or deprecate
  it once the shipped copy is proven.
- **Which models to mirror,** after each one's license check.

## Also

- `doc/privacy_and_licenses.md` lists `cdn.jsdelivr.net` as the browser
  runtime's host; it changes with this, as do the families' READMEs that say
  the runtime loads from jsDelivr.
- `gallery/tool/browser/test_browser.mjs` defaults its runtime root to
  jsDelivr for the comparisons with Google's JavaScript; CI already passes it
  a self-hosted copy.
- One CI run can keep loading from jsDelivr on purpose, as a check that the
  fallback still works, without making every run depend on it.

## Not tried

- Blocking a host in the browser tests (Playwright's `route`) to prove each
  fallback: whether routing sees a dedicated worker's requests in all three
  engines. Pointing a root at a closed local port is the alternative.
- Shipping the files: Flutter's handling of a 21 MB web asset in `flutter
  build web` and `flutter run -d chrome`, and the size of a published
  package with them.
- `If-Range` with each native host's `ETag`.
