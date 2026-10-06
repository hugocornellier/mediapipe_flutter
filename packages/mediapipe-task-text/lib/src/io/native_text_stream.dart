import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'third_party/mediapipe/text_stream_bindings.dart' as mp;

/// Decode a nullable native UTF-8 string before its allocation is released.
String? nativeTextString(Pointer<Char> pointer) =>
    pointer == nullptr ? null : pointer.cast<Utf8>().toDartString();

/// Receive owned copies from the C adapter and drain through the terminal event.
///
/// The adapter posts each copy's address to a port rather than calling a Dart
/// callback: Google may call back after this isolate is gone, after a hot
/// restart for one, and a closed port refuses the message (the adapter then
/// frees the copy) where a deleted callback would abort the VM.
Future<void> receiveNativeTextStream<U>({
  required void Function(Pointer<Void>) submit,
  required U Function(mp.MpFlutterTextEvent, bool) decode,
  required void Function(U) emit,
  required Exception Function(String) exception,
}) async {
  final complete = Completer<void>();
  Object? failure;
  final events = ReceivePort();
  events.listen((message) {
    final address = message as int;
    final event = address > 0
        ? Pointer<mp.MpFlutterTextEvent>.fromAddress(address)
        : nullptr;
    final terminal = event == nullptr
        ? address == mp.lostTerminalEvent
        : event.ref.terminal;
    try {
      if (event == nullptr) {
        throw exception('Could not allocate a streaming result copy.');
      }
      final result = event.ref;
      if (result.copyError != 0) {
        throw exception(
          'Streaming callback copy failed (${result.copyError}).',
        );
      }
      if (result.error != nullptr) {
        throw exception(nativeTextString(result.error)!);
      }
      if (failure == null) emit(decode(result, terminal));
    } catch (error) {
      failure ??= error;
    } finally {
      mp.eventFree(event);
      if (terminal && !complete.isCompleted) {
        if (failure case final error?) {
          complete.completeError(error);
        } else {
          complete.complete();
        }
      }
    }
  });
  Pointer<Void> context = nullptr;
  try {
    context = mp.streamCreate(
      NativeApi.postCObject.cast(),
      events.sendPort.nativePort,
    );
    if (context == nullptr) {
      throw StateError('Could not allocate a streaming context.');
    }
    submit(context);
    await complete.future;
  } finally {
    events.close();
    if (context != nullptr) mp.streamFree(context);
  }
}
