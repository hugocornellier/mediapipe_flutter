"""Make room for Dart install names without relocating code or data.

The pinned upstream dylib has only 40 spare header bytes. Use the equivalent
system framework paths without /Versions/A/, then ad-hoc sign. Section offsets,
virtual addresses, fixups, symbols, code and data remain byte-for-byte intact.
Flutter/Dart perform their normal install-name rewrite and signing afterwards.
"""
import hashlib
import struct
import subprocess


def inspect(data):
    if struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('Expected thin little-endian Mach-O 64')
    count, size = struct.unpack_from('<II', data, 16)
    position, first, signature = 32, len(data), None
    dependencies = []
    sections = []
    for _ in range(count):
        command, length = struct.unpack_from('<II', data, position)
        if command == 0x19:
            nsects = struct.unpack_from('<I', data, position + 64)[0]
            for i in range(nsects):
                start = position + 72 + i * 80
                sections.append(data[start:start + 80])
                offset = struct.unpack_from('<I', data, start + 48)[0]
                if offset:
                    first = min(first, offset)
        if command == 0x1d:
            signature = struct.unpack_from('<I', data, position + 8)[0]
        if command == 0xc:
            at = struct.unpack_from('<I', data, position + 8)[0]
            dependencies.append(data[position + at:position + length].split(b'\0')[0].decode())
        position += length
    if signature is None or position != 32 + size or first < position:
        raise ValueError('Unexpected Mach-O layout')
    return first, signature, first - position, dependencies, sections


def normalize(library):
    original = library.read_bytes()
    before = inspect(original)
    command = ['xcrun', 'install_name_tool']
    for name in before[3]:
        if name.startswith('/System/Library/Frameworks/') and '/Versions/A/' in name:
            command.extend(['-change', name, name.replace('/Versions/A/', '/')])
    subprocess.run([*command, str(library)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                    '--identifier', 'dev.mediapipe.interactive-segmenter', str(library)], check=True)
    modified = library.read_bytes()
    after = inspect(modified)
    if (before[:2] != after[:2] or before[4] != after[4] or
            original[before[0]:before[1]] != modified[after[0]:after[1]]):
        raise ValueError('Packaging changed code, data, section layout or fixups')
    if after[2] < 192:
        raise ValueError('Insufficient install-name header capacity')
    subprocess.run(['codesign', '--verify', '--strict', str(library)], check=True)
    return {
        'method': 'Equivalent system framework paths without /Versions/A/; ad-hoc signature.',
        'unchanged_payload_sha256': hashlib.sha256(original[before[0]:before[1]]).hexdigest(),
        'header_free_bytes': after[2],
        'section_layout_unchanged': True,
    }
