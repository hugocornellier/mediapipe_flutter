// Internal callback-copy adapter ABI; no MediaPipe inference code.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

const _bridge = 'package:mediapipe_flutter_text/text_stream_bridge.dylib';

final class MpCorrection extends Struct {
  @Int32()
  external int type;
  external Pointer<Char> text;
}

final class MpFlutterTextEvent extends Struct {
  external Pointer<Char> text;
  @Int32()
  external int correctionsCount;
  external Pointer<MpCorrection> corrections;
  external Pointer<Char> error;
  @Int32()
  external int copyError;
}

typedef TextEventSink = Void Function(Pointer<MpFlutterTextEvent>, Bool);

@Native<Pointer<Void> Function(Pointer<NativeFunction<TextEventSink>>)>(
  symbol: 'MpFlutterTextStreamCreate',
  assetId: _bridge,
)
external Pointer<Void> streamCreate(
  Pointer<NativeFunction<TextEventSink>> sink,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'MpFlutterTextStreamFree',
  assetId: _bridge,
)
external void streamFree(Pointer<Void> context);

@Native<Void Function(Pointer<MpFlutterTextEvent>)>(
  symbol: 'MpFlutterTextEventFree',
  assetId: _bridge,
)
external void eventFree(Pointer<MpFlutterTextEvent> event);
