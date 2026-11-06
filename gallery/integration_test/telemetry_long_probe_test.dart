import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_gallery/bundled_model_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'support/device_log.dart';
import 'support/sdk_frames.dart';

/// Temporary, one run: whether unpatched 1.2.2 opens any network connection
/// from a real phone over a long life. Only Dart FFI loads the libraries; no
/// JNI_OnLoad, no System.loadLibrary. Downloads no model. Two independent
/// observers run throughout: a sweep of this process's descriptors for any
/// connected internet socket to a non-loopback peer, and the UID's byte
/// counters. One Dart and one Java connection to a non-Google host show that
/// both observers see traffic on this phone in this run.
const _divisor = int.fromEnvironment('PROBE_DIVISOR', defaultValue: 1);
const _controlUrl = 'https://github.com/robots.txt';
const _channel = MethodChannel('probe/net');

Duration _wait(int seconds) => Duration(seconds: seconds) ~/ _divisor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long unpatched 1.2.2 connection watch', timeout: Timeout.none, (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    await tester.runAsync(() async {
      final begun = DateTime.now();
      final phases = <Map<String, Object?>>[];
      Future<List<int>> counters() async {
        final raw = await _channel.invokeListMethod<int>('uidBytes');
        return raw!;
      }

      var last = await counters();
      var closes = 0;
      logRecord('SDK_LONG_START', {'divisor': _divisor, 'counters': last});

      // Runs one phase whatever happens, with the bytes the UID moved in it.
      Future<void> phase(String name, Future<void> Function() body) async {
        final elapsed = DateTime.now().difference(begun);
        if (elapsed > const Duration(minutes: 38)) {
          logRecord('SDK_LONG_SKIPPED', {'phase': name});
          return;
        }
        final started = DateTime.now();
        Object? failure;
        try {
          await body();
        } catch (error) {
          failure = error;
        }
        final next = await counters();
        final record = {
          'phase': name,
          'start_s': started.difference(begun).inSeconds,
          'seconds': DateTime.now().difference(started).inSeconds,
          'tx_bytes': next[0] - last[0],
          'rx_bytes': next[1] - last[1],
          'tx_packets': next[2] - last[2],
          'rx_packets': next[3] - last[3],
          'closes_so_far': closes,
          if (failure != null) 'failure': '$failure',
        };
        last = next;
        phases.add(record);
        logRecord('SDK_LONG_PHASE', record);
      }

      final frame = await loadSample('portrait.jpg');
      final face = await loadAssetBytes(
        bundledModelFile('blaze_face_short_range.tflite'),
      );
      final language = await loadAssetBytes(
        bundledModelFile('language_detector.tflite'),
      );
      final yamnet = await loadAssetBytes(bundledModelFile('yamnet.tflite'));
      final speech = decodeWav(
        await loadAssetBytes('assets/samples/speech_16000_hz_mono.wav'),
      );

      final results = ReceivePort();
      final replies = StreamIterator(results);
      final watcher = await Isolate.spawn(_watch, (
        results.sendPort,
        const Duration(minutes: 42),
      ));
      await replies.moveNext();
      final stop = replies.current as SendPort;

      Future<void> closeEach(int rounds, int gapSeconds) async {
        for (var round = 0; round < rounds; round++) {
          final detector = await FaceDetector.create(
            FaceDetectorOptions(modelBytes: face),
          );
          await detector.detect(frame.image);
          await detector.dispose();
          closes++;
          await Future<void>.delayed(_wait(gapSeconds));
          final text = await LanguageDetector.create(
            LanguageDetectorOptions(modelBytes: language),
          );
          await text.detect('Bonjour tout le monde');
          await text.dispose();
          closes++;
          await Future<void>.delayed(_wait(gapSeconds));
          final audio = await AudioClassifier.create(
            AudioClassifierOptions(modelBytes: yamnet, maxResults: 1),
          );
          await audio.classify(speech);
          await audio.dispose();
          closes++;
          await Future<void>.delayed(_wait(gapSeconds));
        }
      }

      await phase('quiet before any task', () async {
        await Future<void>.delayed(_wait(60));
      });
      await phase('dart control', () async {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(_controlUrl));
        final response = await request.close();
        final body = await response.fold<int>(0, (n, b) => n + b.length);
        logRecord('SDK_LONG_CONTROL', {
          'path': 'dart',
          'status': response.statusCode,
          'bytes': body,
        });
        await Future<void>.delayed(_wait(10));
        client.close(force: true);
      });
      await phase('java control', () async {
        final status = await _channel.invokeMethod<int>('javaGet', _controlUrl);
        logRecord('SDK_LONG_CONTROL', {'path': 'java', 'status': status});
        await Future<void>.delayed(_wait(10));
      });
      await phase('closes 20 s apart', () => closeEach(4, 20));
      await phase('session open with inference', () async {
        final detector = await FaceDetector.create(
          FaceDetectorOptions(modelBytes: face),
        );
        final text = await LanguageDetector.create(
          LanguageDetectorOptions(modelBytes: language),
        );
        final end = DateTime.now().add(_wait(360));
        var calls = 0;
        while (DateTime.now().isBefore(end)) {
          await detector.detect(frame.image);
          await text.detect('Bonjour tout le monde');
          calls++;
          await Future<void>.delayed(_wait(5));
        }
        logRecord('SDK_LONG_SESSION', {'calls': calls});
        await detector.dispose();
        closes++;
        await text.dispose();
        closes++;
      });
      await phase('quiet after session', () async {
        await Future<void>.delayed(_wait(150));
      });
      await phase('quiet in foreground', () async {
        await Future<void>.delayed(_wait(240));
      });
      await phase('in background', () async {
        await _channel.invokeMethod<void>('background');
        await Future<void>.delayed(_wait(300));
      });
      await phase('back in foreground', () async {
        await _channel.invokeMethod<void>('foreground');
        await Future<void>.delayed(_wait(30));
      });
      await phase('closes 4 s apart', () => closeEach(4, 4));
      await phase('quiet to the end', () async {
        await Future<void>.delayed(_wait(150));
      });

      stop.send(null);
      await replies.moveNext();
      final (sweeps, seen) =
          replies.current as (int, List<Map<String, Object?>>);
      watcher.kill();
      await replies.cancel();
      for (final entry in seen) {
        logRecord('SDK_LONG_SOCKET_FINAL', entry);
      }
      logRecord('SDK_LONG_SUMMARY', {
        'internet_sockets': seen.length,
        'closes': closes,
        'sweeps': sweeps,
        'total_seconds': DateTime.now().difference(begun).inSeconds,
        'phases': phases.length,
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

bool _isLoopback(InternetAddress ip) =>
    ip.isLoopback || ip.address.startsWith('::ffff:127.');

/// The sweep of telemetry_probe_test.dart, for any port and either socket
/// type, logging each new connection at once so a timeout still leaves it.
Future<void> _watch((SendPort, Duration) args) async {
  final (reply, window) = args;
  final control = ReceivePort();
  var stopped = false;
  control.listen((_) => stopped = true);
  reply.send(control.sendPort);
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
  final origin = DateTime.now();
  final end = origin.add(window);
  var sweeps = 0;
  while (!stopped && DateTime.now().isBefore(end)) {
    for (var fd = 0; fd < 2048; fd++) {
      length.value = 128;
      if (getpeername(fd, address, length) != 0) continue;
      final bytes = address.asTypedList(128);
      final family = bytes[0] | bytes[1] << 8;
      if (family != 2 && family != 10) continue;
      final port = bytes[2] << 8 | bytes[3];
      final ip = family == 2
          ? InternetAddress.fromRawAddress(
              Uint8List.fromList(bytes.sublist(4, 8)),
            )
          : InternetAddress.fromRawAddress(
              Uint8List.fromList(bytes.sublist(8, 24)),
            );
      if (_isLoopback(ip)) continue;
      // SOL_SOCKET 1, SO_TYPE 3: 1 is TCP, 2 is UDP.
      length.value = 4;
      final typed = getsockopt(fd, 1, 3, info, length) == 0
          ? info.cast<Int32>().value
          : 0;
      length.value = 256;
      // IPPROTO_TCP 6, TCP_INFO 11; tcpi_bytes_acked at 120 and
      // tcpi_bytes_received at 128 (Linux 4.1+).
      final ok =
          typed == 1 &&
          getsockopt(fd, 6, 11, info, length) == 0 &&
          length.value >= 136;
      final view = ByteData.sublistView(info.asTypedList(256));
      length.value = 128;
      final own = getsockname(fd, local, length) == 0
          ? local[2] << 8 | local[3]
          : 0;
      final key = '$fd ${ip.address} $own';
      final at = DateTime.now().difference(origin).inMilliseconds;
      var entry = seen[key];
      if (entry == null) {
        entry = {
          'fd': fd,
          'peer': ip.address,
          'port': port,
          'type': typed,
          'local_port': own,
          'first_ms': at,
        };
        seen[key] = entry;
        logRecord('SDK_LONG_SOCKET_NEW', entry);
      }
      entry['last_ms'] = at;
      if (ok) {
        entry['bytes_acked'] = view.getUint64(120, Endian.host);
        entry['bytes_received'] = view.getUint64(128, Endian.host);
      }
    }
    sweeps++;
    if (sweeps % 50 == 0) await Future<void>.delayed(Duration.zero);
    if (sweeps % 100000 == 0) {
      logRecord('SDK_LONG_SWEEP', {
        'sweeps': sweeps,
        'seconds': DateTime.now().difference(origin).inSeconds,
      });
    }
  }
  control.close();
  reply.send((sweeps, seen.values.toList()));
}
