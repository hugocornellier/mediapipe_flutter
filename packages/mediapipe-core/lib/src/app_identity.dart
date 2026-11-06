import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The app's ID and version as Google's native SDKs report them. Null off the
/// platforms below, or where the platform does not give them: reading them must
/// never stop a task from starting.
///
/// Tasks start on worker isolates, so this runs synchronously on any isolate.
/// On iOS: the bundle ID and `CFBundleShortVersionString`, through
/// CoreFoundation, which every iOS process loads.
({String? id, String? version}) readAppIdentity() {
  try {
    if (Platform.isIOS) return _readBundle();
  } catch (_) {}
  return (id: null, version: null);
}

typedef _CFBundleGetMainBundleNative = Pointer<Void> Function();
typedef _CFBundleGetIdentifierNative = Pointer<Void> Function(Pointer<Void>);
typedef _CFBundleGetValueNative =
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _CFStringCreateNative =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreate =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CFStringGetCStringNative =
    Bool Function(Pointer<Void>, Pointer<Utf8>, IntPtr, Uint32);
typedef _CFStringGetCString =
    bool Function(Pointer<Void>, Pointer<Utf8>, int, int);
typedef _CFGetTypeIDNative = UnsignedLong Function(Pointer<Void>);
typedef _CFGetTypeID = int Function(Pointer<Void>);
typedef _CFStringGetTypeIDNative = UnsignedLong Function();
typedef _CFStringGetTypeID = int Function();
typedef _CFReleaseNative = Void Function(Pointer<Void>);
typedef _CFRelease = void Function(Pointer<Void>);

// kCFStringEncodingUTF8.
const _utf8 = 0x08000100;

({String? id, String? version}) _readBundle() {
  final cf = DynamicLibrary.process();
  final mainBundle = cf
      .lookupFunction<
        _CFBundleGetMainBundleNative,
        _CFBundleGetMainBundleNative
      >('CFBundleGetMainBundle');
  final getIdentifier = cf
      .lookupFunction<
        _CFBundleGetIdentifierNative,
        _CFBundleGetIdentifierNative
      >('CFBundleGetIdentifier');
  final getValue = cf
      .lookupFunction<_CFBundleGetValueNative, _CFBundleGetValueNative>(
        'CFBundleGetValueForInfoDictionaryKey',
      );
  final createString = cf
      .lookupFunction<_CFStringCreateNative, _CFStringCreate>(
        'CFStringCreateWithCString',
      );
  final getCString = cf
      .lookupFunction<_CFStringGetCStringNative, _CFStringGetCString>(
        'CFStringGetCString',
      );
  final getTypeId = cf.lookupFunction<_CFGetTypeIDNative, _CFGetTypeID>(
    'CFGetTypeID',
  );
  final stringTypeId = cf
      .lookupFunction<_CFStringGetTypeIDNative, _CFStringGetTypeID>(
        'CFStringGetTypeID',
      );
  final release = cf.lookupFunction<_CFReleaseNative, _CFRelease>('CFRelease');

  return using((arena) {
    String? read(Pointer<Void> string) {
      if (string == nullptr || getTypeId(string) != stringTypeId()) return null;
      const capacity = 1024;
      final buffer = arena<Uint8>(capacity).cast<Utf8>();
      if (!getCString(string, buffer, capacity, _utf8)) return null;
      final value = buffer.toDartString();
      return value.isEmpty ? null : value;
    }

    final bundle = mainBundle();
    if (bundle == nullptr) return (id: null, version: null);
    final key = createString(
      nullptr,
      'CFBundleShortVersionString'.toNativeUtf8(allocator: arena),
      _utf8,
    );
    try {
      return (
        id: read(getIdentifier(bundle)),
        version: read(getValue(bundle, key)),
      );
    } finally {
      release(key);
    }
  });
}
