import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_gallery/bundled_model_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'support/device_log.dart';
import 'support/sdk_frames.dart';

/// Whether Google's usage logger uploads from a real Android phone: runs Face
/// Detector and Language Detector, closes each, and meanwhile watches this
/// process's own sockets from another isolate. Any connected TCP socket to
/// port 443 is logged with its peer and the bytes TCP_INFO counts for it, so
/// the log shows whether a close opened a connection and how much it carried.
/// The API 31 emulator, through a TLS proxy, showed one connection per close to
/// play.googleapis.com carrying a POST /log that Google answered with 200.
/// Reports only: it never fails on what the network did.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('usage-log connections at task close', (tester) async {
    if (!Platform.isAndroid) return;
    await tester.runAsync(() async {
      final results = ReceivePort();
      final marks = <String, int>{};
      int now() => DateTime.now().microsecondsSinceEpoch;
      final watcher = await Isolate.spawn(_watch, (
        results.sendPort,
        const Duration(seconds: 40),
      ));
      await Future<void>.delayed(const Duration(seconds: 2));

      final frame = await loadSample('portrait.jpg');
      final face = await loadAssetBytes(
        bundledModelFile('blaze_face_short_range.tflite'),
      );
      final language = await loadAssetBytes(
        bundledModelFile('language_detector.tflite'),
      );
      for (var round = 0; round < 2; round++) {
        final detector = await FaceDetector.create(
          FaceDetectorOptions(modelBytes: face),
        );
        final faces = (await detector.detect(frame.image)).detections.length;
        marks['face $round close start'] = now();
        await detector.dispose();
        marks['face $round close end'] = now();
        logRecord('SDK_TELEMETRY_TASK', {
          'task': 'face_detector',
          'round': round,
          'faces': faces,
        });
        await Future<void>.delayed(const Duration(seconds: 3));

        final text = await LanguageDetector.create(
          LanguageDetectorOptions(modelBytes: language),
        );
        final top = (await text.detect(
          'Bonjour tout le monde',
        )).predictions.first.languageCode;
        marks['language $round close start'] = now();
        await text.dispose();
        marks['language $round close end'] = now();
        logRecord('SDK_TELEMETRY_TASK', {
          'task': 'language_detector',
          'round': round,
          'top': top,
        });
        await Future<void>.delayed(const Duration(seconds: 3));
      }

      final (sweeps, seen) =
          await results.first as (int, List<Map<String, Object?>>);
      watcher.kill();
      results.close();
      String? during(int first, int last) {
        for (final name in marks.keys.where((k) => k.endsWith('start'))) {
          final start = marks[name]!;
          final end = marks[name.replaceFirst('start', 'end')]!;
          if (first <= end + 2000000 && last >= start) {
            return name.replaceFirst(' close start', '');
          }
        }
        return null;
      }

      final origin = marks.values.reduce((a, b) => a < b ? a : b);
      for (final entry in seen) {
        logRecord('SDK_TELEMETRY_SOCKET', {
          ...entry,
          'first_ms': ((entry['first'] as int) - origin) ~/ 1000,
          'last_ms': ((entry['last'] as int) - origin) ~/ 1000,
          'during_close_of': during(
            entry['first'] as int,
            entry['last'] as int,
          ),
        });
      }
      logRecord('SDK_TELEMETRY_MARKS', {
        for (final MapEntry(:key, :value) in marks.entries)
          key: (value - origin) ~/ 1000,
      });
      logRecord('SDK_TELEMETRY_SUMMARY', {
        'sockets_443': seen.length,
        'during_close': seen
            .where((e) => during(e['first'] as int, e['last'] as int) != null)
            .length,
        'closes': marks.length ~/ 2,
        'sweeps': sweeps,
      });
    });
  });
}

typedef _PeerNative = Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint32>);
typedef _Peer = int Function(int, Pointer<Uint8>, Pointer<Uint32>);
typedef _OptNative =
    Int32 Function(Int32, Int32, Int32, Pointer<Uint8>, Pointer<Uint32>);
typedef _Opt = int Function(int, int, int, Pointer<Uint8>, Pointer<Uint32>);
typedef _MallocNative = Pointer<Uint8> Function(IntPtr);
typedef _Malloc = Pointer<Uint8> Function(int);

/// Sweeps file descriptors 0..2047 for connected internet sockets with peer
/// port 443 until the window ends, then sends one record per connection seen.
Future<void> _watch((SendPort, Duration) args) async {
  final (reply, window) = args;
  final libc = DynamicLibrary.process();
  final getpeername = libc.lookupFunction<_PeerNative, _Peer>('getpeername');
  final getsockname = libc.lookupFunction<_PeerNative, _Peer>('getsockname');
  final getsockopt = libc.lookupFunction<_OptNative, _Opt>('getsockopt');
  final malloc = libc.lookupFunction<_MallocNative, _Malloc>('malloc');
  final address = malloc(128);
  final local = malloc(128);
  final info = malloc(256);
  final length = malloc(4).cast<Uint32>();
  final seen = <String, Map<String, Object?>>{};
  final end = DateTime.now().add(window);
  var sweeps = 0;
  while (DateTime.now().isBefore(end)) {
    for (var fd = 0; fd < 2048; fd++) {
      length.value = 128;
      if (getpeername(fd, address, length) != 0) continue;
      final bytes = address.asTypedList(128);
      final family = bytes[0] | bytes[1] << 8;
      if (family != 2 && family != 10) continue;
      final port = bytes[2] << 8 | bytes[3];
      if (port != 443) continue;
      final ip = family == 2
          ? InternetAddress.fromRawAddress(
              Uint8List.fromList(bytes.sublist(4, 8)),
            )
          : InternetAddress.fromRawAddress(
              Uint8List.fromList(bytes.sublist(8, 24)),
            );
      length.value = 256;
      // IPPROTO_TCP 6, TCP_INFO 11; tcpi_bytes_acked at 120 and
      // tcpi_bytes_received at 128 (Linux 4.1+).
      final ok =
          getsockopt(fd, 6, 11, info, length) == 0 && length.value >= 136;
      final view = ByteData.sublistView(info.asTypedList(256));
      // A later connection can reuse the descriptor; its local port differs.
      length.value = 128;
      final own = getsockname(fd, local, length) == 0
          ? local[2] << 8 | local[3]
          : 0;
      final key = '$fd ${ip.address} $own';
      final now = DateTime.now().microsecondsSinceEpoch;
      final entry = seen.putIfAbsent(
        key,
        () => {
          'fd': fd,
          'peer': ip.address,
          'port': port,
          'local_port': own,
          'first': now,
        },
      );
      entry['last'] = now;
      if (ok) {
        entry['bytes_acked'] = view.getUint64(120, Endian.host);
        entry['bytes_received'] = view.getUint64(128, Endian.host);
      }
    }
    sweeps++;
    // Yields to the event loop now and then; a sweep is about a millisecond.
    if (sweeps % 50 == 0) await Future<void>.delayed(Duration.zero);
  }
  reply.send((sweeps, seen.values.toList()));
}
