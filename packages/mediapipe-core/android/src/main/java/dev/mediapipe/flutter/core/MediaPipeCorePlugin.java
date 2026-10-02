package dev.mediapipe.flutter.core;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Registers nothing: this library exists for the family plugins, which build their Android
 * plugins on {@link TaskHost}. Flutter includes an Android library only for a package that
 * declares a plugin class, so this one is declared and does nothing.
 */
public final class MediaPipeCorePlugin implements FlutterPlugin {
  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {}

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {}
}
