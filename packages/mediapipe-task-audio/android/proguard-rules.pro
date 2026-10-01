# Google's MediaPipe Android SDKs ship no R8 rules, and Flutter shrinks every
# release build, so without these a release app cannot create a task.
#
# Their native code reaches the Java classes by name (JNI), and Graph's logger
# (Flogger) finds its caller by class name on the stack.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.common.flogger.** { *; }
# Kept whole, the framework names profiler and graph template protos that the
# SDKs leave out; tasks never reach them.
-dontwarn com.google.mediapipe.proto.**
# Kept whole, the framework's image classes also name AutoValue's annotations,
# which are compile-only and ship in no AAR. An app with CameraX gets them
# along with it; any other release build would fail to shrink.
-dontwarn com.google.auto.value.**
# This plugin swaps protobuf-javalite for full protobuf-java
# (google-ai-edge/mediapipe#6348). The full runtime finds its schema factories
# by class name, and the SDKs' lite messages are read by field name, a rule
# javalite would have shipped.
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
}
