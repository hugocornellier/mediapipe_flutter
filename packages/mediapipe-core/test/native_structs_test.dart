@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/native_structs.dart';
import 'package:test/test.dart';

void main() {
  group('checkNativeStatus', () {
    late List<Pointer<Char>> freed;
    void errorFree(Pointer<Char> message) {
      freed.add(message);
      malloc.free(message);
    }

    /// A call that reports [status] and, unless [message] is null, a message
    /// Google's library would allocate.
    int Function(Pointer<Pointer<Char>>) reporting(
      int status,
      String? message,
    ) => (error) {
      if (message != null) error.value = message.toNativeUtf8().cast();
      return status;
    };

    setUp(() => freed = []);

    test('an OK status passes and frees a message', () {
      checkNativeStatus(reporting(0, null), errorFree);
      expect(freed, isEmpty);
      checkNativeStatus(reporting(0, 'warning'), errorFree);
      expect(freed, hasLength(1));
    });

    test("a failure throws Google's message and status, freed", () {
      expect(
        () => checkNativeStatus(reporting(3, 'bad model'), errorFree),
        throwsA(
          isA<TaskException>()
              .having((e) => e.message, 'message', 'bad model')
              .having((e) => e.statusCode, 'statusCode', 3),
        ),
      );
      expect(freed, hasLength(1));
    });

    test('a failure without a message names its status', () {
      expect(
        () => checkNativeStatus(reporting(5, null), errorFree),
        throwsA(
          isA<TaskException>().having(
            (e) => e.message,
            'message',
            contains('status 5'),
          ),
        ),
      );
      expect(freed, isEmpty);
    });

    test('an empty message stays empty', () {
      expect(
        () => checkNativeStatus(reporting(2, ''), errorFree),
        throwsA(isA<TaskException>().having((e) => e.message, 'message', '')),
      );
      expect(freed, hasLength(1));
    });

    test("failure rewrites the error, and Google's message is still freed", () {
      expect(
        () => checkNativeStatus(
          reporting(3, 'EG2 embedder'),
          errorFree,
          failure: (message, status) =>
              TaskException('$message: use another model', statusCode: status),
        ),
        throwsA(
          isA<TaskException>().having(
            (e) => e.message,
            'message',
            'EG2 embedder: use another model',
          ),
        ),
      );
      expect(
        () => checkNativeStatus(
          reporting(3, 'boom'),
          errorFree,
          failure: (message, status) => throw StateError(message),
        ),
        throwsStateError,
      );
      expect(freed, hasLength(2));
    });
  });

  test('nativeString copies, and reads empty as absent on request', () {
    expect(nativeString(nullptr), isNull);
    using((arena) {
      final empty = ''.toNativeUtf8(allocator: arena).cast<Char>();
      final text = 'hello'.toNativeUtf8(allocator: arena).cast<Char>();
      expect(nativeString(empty), '');
      expect(nativeString(empty, emptyIsNull: true), isNull);
      expect(nativeString(text, emptyIsNull: true), 'hello');
    });
  });
}
