// Internal callback-copy adapter ABI; no MediaPipe inference code.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

const _bridge = 'package:mediapipe_text/text_stream_bridge.dylib';

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
  @Bool()
  external bool terminal;
}

/// What the bridge posts in place of an event's address when its copy could
/// not be allocated (kMpFlutterTextLostEvent).
const lostEvent = -1;

/// What the bridge posts in place of the last event's address when its copy
/// could not be allocated (kMpFlutterTextLostTerminalEvent).
const lostTerminalEvent = -2;

@Native<Pointer<Void> Function(Pointer<Void>, Int64)>(
  symbol: 'MpFlutterTextStreamCreate',
  assetId: _bridge,
)
external Pointer<Void> streamCreate(Pointer<Void> post, int port);

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
