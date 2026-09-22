/// Whether the page publishes per-frame state on the camera's video element
/// (`data-*` attributes and the overlay alignment probes) for the browser test
/// suite, `tool/browser/test_browser.mjs`, which loads the gallery with
/// `?test-hooks`. Off for everyone else, since the writes cost main-thread time
/// on every frame.
final bool testHooks = Uri.base.queryParameters.containsKey('test-hooks');
