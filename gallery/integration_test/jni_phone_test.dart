// ignore_for_file: depend_on_referenced_packages, invalid_use_of_internal_member
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jni/jni.dart';
import 'package:mediapipe_gallery/bundled_model_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

import 'support/device_log.dart';

/// One question on a real phone, in one process: does calling the text
/// library's exported JNI_OnLoad from Dart restore the usage uploader, without
/// a crash or a slowdown? Temporary, for the branch test/jni-phone only.
///
/// Windows, in order, on the text family alone (Language Detector, its model
/// bundled, so nothing downloads): warm-up, idle (the noise floor), unfixed
/// cycles, the call, fixed cycles, and last a positive control that fetches
/// one URL, to show the network works and the counters see traffic. Each window
/// logs this UID's TrafficStats bytes, and a watcher isolate logs each connected
/// non-loopback socket this process holds. Logcat's line counts are split on
/// the JNI_PHONE_PHASE lines afterwards.
///
/// Fails only on a crash or a wrong return code: what the network did is for
/// the log. It shows bytes, not their contents, so it cannot say what was
/// uploaded or whether the server kept it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JNI_OnLoad from Dart on a phone', (tester) async {
    if (!Platform.isAndroid) return;
    final code = await tester.runAsync(_run);
    expect(code, _jniVersion16);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// JNI_VERSION_1_6, what the library's JNI_OnLoad returns.
const _jniVersion16 = 0x10006;
const _library = 'libmediapipe_tasks_text.so';
const _cycles = 10;
const _cycleGap = Duration(seconds: 1);
const _settle = Duration(seconds: 25);

typedef _OnLoadNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _OnLoad = int Function(Pointer<Void>, Pointer<Void>);

Future<int> _run() async {
  _logDevice();
  final uid = _myUid();
  final model = await loadBundledModel('language_detector.tflite');
  logRecord('JNI_PHONE_MODEL', {'bytes': model.length, 'uid': uid});

  final results = ReceivePort();
  final replies = StreamIterator(results);
  final watcher = await Isolate.spawn(_watch, results.sendPort);
  await replies.moveNext();
  final stop = replies.current as SendPort;

  final windows = <Map<String, Object?>>[];
  Future<T> window<T>(String name, Future<T> Function() body) async {
    final start = DateTime.now().microsecondsSinceEpoch;
    final before = _traffic(uid);
    logRecord('JNI_PHONE_PHASE', {'phase': name, 'edge': 'start', ...before});
    final value = await body();
    final after = _traffic(uid);
    final end = DateTime.now().microsecondsSinceEpoch;
    final record = {
      'phase': name,
      'edge': 'end',
      'seconds': (end - start) ~/ 1000000,
      'tx_start': before['tx'],
      'tx_end': after['tx'],
      'tx_delta': _delta(before['tx'], after['tx']),
      'rx_delta': _delta(before['rx'], after['rx']),
    };
    logRecord('JNI_PHONE_PHASE', record);
    windows.add({...record, 'start': start, 'end': end});
    return value;
  }

  Future<void> cycles(String name) async {
    final creates = <double>[];
    final detects = <double>[];
    final closes = <double>[];
    for (var i = 0; i < _cycles; i++) {
      final (create, detect, close) = await _cycle(model);
      creates.add(create);
      detects.add(detect);
      closes.add(close);
      logRecord('JNI_PHONE_CYCLE', {
        'phase': name,
        'i': i,
        'create_ms': create,
        'detect_ms': detect,
        'close_ms': close,
      });
      await Future<void>.delayed(_cycleGap);
    }
    logRecord('JNI_PHONE_TIMES', {
      'phase': name,
      'cycles': _cycles,
      'close_ms': _spread(closes),
      'create_ms': _spread(creates),
      'detect_ms': _spread(detects),
    });
    await Future<void>.delayed(_settle);
  }

  await window('warmup', () async {
    await _cycle(model);
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  await window('idle', () => Future<void>.delayed(const Duration(seconds: 20)));
  await window('unfixed', () => cycles('unfixed'));
  final code = await window('after_call', () async {
    final code = _callOnLoad();
    await Future<void>.delayed(const Duration(seconds: 10));
    return code;
  });
  await window('fixed', () => cycles('fixed'));
  await window('control', _control);

  stop.send(null);
  await replies.moveNext();
  final (sweeps, seen) = replies.current as (int, List<Map<String, Object?>>);
  watcher.kill();
  await replies.cancel();
  final origin = windows.first['start'] as int;
  String phaseOf(int time) {
    for (final w in windows) {
      if (time >= (w['start'] as int) && time <= (w['end'] as int)) {
        return w['phase'] as String;
      }
    }
    return 'outside';
  }

  final perPhase = <String, int>{};
  for (final entry in seen) {
    final phase = phaseOf(entry['first'] as int);
    perPhase[phase] = (perPhase[phase] ?? 0) + 1;
    logRecord('JNI_PHONE_SOCKET', {
      ...entry,
      'phase': phase,
      'first_ms': ((entry['first'] as int) - origin) ~/ 1000,
      'last_ms': ((entry['last'] as int) - origin) ~/ 1000,
    });
  }
  logRecord('JNI_PHONE_SUMMARY', {
    'return_code': '0x${code.toRadixString(16)}',
    'sockets_first_seen_in': perPhase,
    'sweeps': sweeps,
    for (final w in windows) '${w['phase']}_tx_delta': w['tx_delta'],
  });
  return code;
}

/// Times one create, detect and close, in milliseconds.
Future<(double, double, double)> _cycle(Uint8List model) async {
  final watch = Stopwatch()..start();
  final task = await LanguageDetector.create(
    LanguageDetectorOptions(modelBytes: model),
  );
  final create = watch.elapsedMicroseconds / 1000;
  watch.reset();
  await task.detect('Bonjour tout le monde');
  final detect = watch.elapsedMicroseconds / 1000;
  watch.reset();
  await task.dispose();
  return (create, detect, watch.elapsedMicroseconds / 1000);
}

int _callOnLoad() {
  final vm = calloc<Pointer<Void>>();
  final got = Jni.env.GetJavaVM(vm.cast());
  final onLoad = DynamicLibrary.open(
    _library,
  ).lookupFunction<_OnLoadNative, _OnLoad>('JNI_OnLoad');
  final watch = Stopwatch()..start();
  final code = onLoad(vm.value, nullptr);
  logRecord('JNI_PHONE_CALL', {
    'library': _library,
    'get_java_vm': got,
    'vm_set': vm.value != nullptr,
    'return_code': '0x${code.toRadixString(16)}',
    'call_us': watch.elapsedMicroseconds,
  });
  calloc.free(vm);
  return code;
}

/// After every measured window: shows the phone can reach the internet and
/// that TrafficStats and the watcher count what this process sends, and which
/// addresses the log's host has now, to compare with the sockets' peers.
Future<void> _control() async {
  try {
    final addresses = await InternetAddress.lookup('play.googleapis.com');
    logRecord('JNI_PHONE_CONTROL', {
      'host': 'play.googleapis.com',
      'addresses': [for (final a in addresses) a.address],
    });
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('https://www.gstatic.com/generate_204'),
    );
    final response = await request.close();
    await response.drain<void>();
    logRecord('JNI_PHONE_CONTROL', {'status': response.statusCode});
    // Keeps the socket open a moment, for the watcher.
    await Future<void>.delayed(const Duration(seconds: 2));
    client.close(force: true);
  } on Object catch (error) {
    logRecord('JNI_PHONE_CONTROL', {'error': '$error'});
  }
  await Future<void>.delayed(const Duration(seconds: 3));
}

Map<String, Object?> _spread(List<double> values) {
  final sorted = [...values]..sort();
  return {
    'min': sorted.first,
    'median': sorted[sorted.length ~/ 2],
    'max': sorted.last,
  };
}

int? _delta(Object? before, Object? after) =>
    before is int && after is int && before >= 0 && after >= 0
    ? after - before
    : null;

int _myUid() {
  try {
    final process = JClass.forName('android/os/Process');
    return process.staticMethodId('myUid', '()I')(process, jint.type, const []);
  } on Object catch (error) {
    logRecord('JNI_PHONE_ERROR', {'myUid': '$error'});
    return -1;
  }
}

/// This UID's bytes so far; a read that fails is logged, and does not stop the
/// test, since the watcher's sockets still count.
Map<String, Object?> _traffic(int uid) {
  try {
    final stats = JClass.forName('android/net/TrafficStats');
    int read(String method) => stats.staticMethodId(method, '(I)J')(
      stats,
      jlong.type,
      [JValueInt(uid)],
    );
    return {'tx': read('getUidTxBytes'), 'rx': read('getUidRxBytes')};
  } on Object catch (error) {
    logRecord('JNI_PHONE_ERROR', {'traffic': '$error'});
    return {'tx': null, 'rx': null};
  }
}

void _logDevice() {
  try {
    final build = JClass.forName('android/os/Build');
    final version = JClass.forName(r'android/os/Build$VERSION');
    String text(JClass from, String field) => from
        .staticFieldId(field, 'Ljava/lang/String;')
        .get(from, JString.type)
        .toDartString();
    logRecord('JNI_PHONE_DEVICE', {
      'manufacturer': text(build, 'MANUFACTURER'),
      'model': text(build, 'MODEL'),
      'device': text(build, 'DEVICE'),
      'release': text(version, 'RELEASE'),
      'sdk': version.staticFieldId('SDK_INT', 'I').get(version, jint.type),
    });
  } on Object catch (error) {
    logRecord('JNI_PHONE_ERROR', {'device': '$error'});
  }
}

typedef _PeerNative = Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint32>);
typedef _Peer = int Function(int, Pointer<Uint8>, Pointer<Uint32>);
typedef _OptNative =
    Int32 Function(Int32, Int32, Int32, Pointer<Uint8>, Pointer<Uint32>);
typedef _Opt = int Function(int, int, int, Pointer<Uint8>, Pointer<Uint32>);
typedef _MallocNative = Pointer<Uint8> Function(IntPtr);
typedef _Malloc = Pointer<Uint8> Function(int);

/// From telemetry_probe_test.dart, with any port and a pause between sweeps, so
/// the timings keep their cores: sweeps descriptors 0..2047 for connected
/// non-loopback internet sockets until told to stop, then sends one record per
/// connection seen. Its first message is the port that stops it.
Future<void> _watch(SendPort reply) async {
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
  final end = DateTime.now().add(const Duration(minutes: 8));
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
      if (ip.isLoopback) continue;
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  control.close();
  reply.send((sweeps, seen.values.toList()));
}
