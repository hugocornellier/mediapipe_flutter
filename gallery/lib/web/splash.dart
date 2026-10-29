import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fades out web/index.html's loading screen, which covers the page while
/// Flutter's engine and the app download.
void hideSplash() {
  final splash = web.document.getElementById('splash');
  if (splash == null || splash.classList.contains('done')) return;
  splash.classList.add('done');
  splash.addEventListener('transitionend', ((web.Event _) => splash.remove()).toJS);
}
