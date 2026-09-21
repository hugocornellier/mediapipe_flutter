import 'dart:convert';
import 'dart:typed_data';

/// Builds the smallest signed thin arm64 Mach-O the validator needs to see:
/// a header, an `LC_ID_DYLIB`, a `__LINKEDIT` segment, an `LC_CODE_SIGNATURE`,
/// some payload bytes and a signature blob at the end of the file.
///
/// Every field `codesign` rewrites is derived from [signature] so tests can
/// vary the blob exactly as a different Xcode would.
Uint8List syntheticSignedMachO({
  List<int> payload = const [1, 2, 3, 4],
  List<int> signature = const [0xfa, 0xde, 0x0c, 0xc0],
  String installName = '@rpath/libmediapipe.dylib',
}) {
  final name = ascii.encode(installName);
  final idLength = _align(24 + name.length + 1, 8);
  const segmentLength = 72;
  const signatureLength = 16;
  final commandsLength = idLength + segmentLength + signatureLength;
  final payloadOffset = 32 + commandsLength;
  final signatureOffset = _align(payloadOffset + payload.length, 16);
  final total = signatureOffset + signature.length;
  final bytes = Uint8List(total);
  final view = ByteData.sublistView(bytes);

  // mach_header_64
  view.setUint32(0, 0xfeedfacf, Endian.little);
  view.setUint32(4, 0x0100000c, Endian.little); // CPU_TYPE_ARM64
  view.setUint32(8, 0, Endian.little);
  view.setUint32(12, 6, Endian.little); // MH_DYLIB
  view.setUint32(16, 3, Endian.little); // ncmds
  view.setUint32(20, commandsLength, Endian.little);
  view.setUint32(24, 0, Endian.little);

  // LC_ID_DYLIB
  var position = 32;
  view.setUint32(position, 0xd, Endian.little);
  view.setUint32(position + 4, idLength, Endian.little);
  view.setUint32(position + 8, 24, Endian.little); // name offset
  bytes.setRange(position + 24, position + 24 + name.length, name);
  position += idLength;

  // LC_SEGMENT_64 __LINKEDIT, sized to include the signature blob.
  view.setUint32(position, 0x19, Endian.little);
  view.setUint32(position + 4, segmentLength, Endian.little);
  bytes.setRange(position + 8, position + 18, ascii.encode('__LINKEDIT'));
  final linkeditSize = total - payloadOffset;
  view.setUint64(position + 24, 0x4000, Endian.little); // vmaddr
  view.setUint64(position + 32, linkeditSize, Endian.little); // vmsize
  view.setUint64(position + 40, payloadOffset, Endian.little); // fileoff
  view.setUint64(position + 48, linkeditSize, Endian.little); // filesize
  position += segmentLength;

  // LC_CODE_SIGNATURE
  view.setUint32(position, 0x1d, Endian.little);
  view.setUint32(position + 4, signatureLength, Endian.little);
  view.setUint32(position + 8, signatureOffset, Endian.little);
  view.setUint32(position + 12, signature.length, Endian.little);

  bytes.setRange(payloadOffset, payloadOffset + payload.length, payload);
  bytes.setRange(signatureOffset, total, signature);
  return bytes;
}

int _align(int value, int to) => (value + to - 1) ~/ to * to;
