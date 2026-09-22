"""Make room for Dart install names without relocating code or data.

The pinned upstream dylib has only 40 spare header bytes. Use the equivalent
system framework paths without /Versions/A/, then ad-hoc sign. Section offsets,
virtual addresses, fixups, symbols, code and data remain byte-for-byte intact.
Flutter/Dart perform their normal install-name rewrite and signing afterwards.
"""
import hashlib
import re
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


def unsigned_sha256(data):
    """SHA-256 of a signed thin Mach-O with its code signature masked out.

    codesign rewrites exactly three things when it re-signs a dylib: the
    signature blob at the end of __LINKEDIT, that segment's vmsize/filesize,
    and LC_CODE_SIGNATURE's dataoff/datasize. Different Xcode releases emit
    different blobs, so a pin on the signed file breaks with a toolchain
    update. Hashing everything before the blob, with those fields zeroed,
    pins the header (including the rewritten install names), code, data and
    fixups, and nothing the signer chooses. The Dart hook computes the same
    digest in unsignedMachOSha256.
    """
    if struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('Expected thin little-endian Mach-O 64')
    count = struct.unpack_from('<I', data, 16)[0]
    image = bytearray(data)
    position, end = 32, len(data)
    for _ in range(count):
        command, length = struct.unpack_from('<II', data, position)
        if command == 0x19 and data[position + 8:position + 24].rstrip(b'\0') == b'__LINKEDIT':
            # vmsize at +32 and filesize at +48; fileoff between them stays.
            image[position + 32:position + 40] = bytes(8)
            image[position + 48:position + 56] = bytes(8)
        if command == 0x1d:
            end = struct.unpack_from('<I', data, position + 8)[0]
            image[position + 8:position + 16] = bytes(8)
        position += length
    return hashlib.sha256(image[:end]).hexdigest()


def install_name(data):
    """Return the thin dylib's LC_ID_DYLIB string."""
    count = struct.unpack_from('<I', data, 16)[0]
    position = 32
    for _ in range(count):
        command, length = struct.unpack_from('<II', data, position)
        if command == 0xd:
            at = struct.unpack_from('<I', data, position + 8)[0]
            return data[position + at:position + length].split(b'\0')[0].decode()
        position += length
    raise ValueError('Mach-O dylib has no LC_ID_DYLIB')


def rewrite_install_name(library, name):
    """Rewrite only LC_ID_DYLIB/signing metadata and prove payload identity."""
    original = library.read_bytes()
    before = inspect(original)
    original_name = install_name(original)
    command = ['xcrun', 'install_name_tool', '-id', name]
    replacements = {}
    for dependency in before[3]:
        if (dependency.startswith('/System/Library/Frameworks/') and
                '/Versions/' in dependency):
            shortened = re.sub(r'/Versions/[A-Z]/', '/', dependency)
            replacements[dependency] = shortened
            command.extend(['-change', dependency, shortened])
    subprocess.run([*command, str(library)], check=True)
    subprocess.run(['codesign', '-f', '-s', '-', str(library)], check=True)
    modified = library.read_bytes()
    after = inspect(modified)
    expected_dependencies = [replacements.get(item, item) for item in before[3]]
    if (before[:2] != after[:2] or before[4] != after[4] or
            after[3] != expected_dependencies or
            original[before[0]:before[1]] != modified[after[0]:after[1]]):
        raise ValueError('Install-name packaging changed code, data, layout or fixups')
    if install_name(modified) != name:
        raise ValueError('install_name_tool did not set the requested LC_ID_DYLIB')
    if after[2] < 192:
        raise ValueError('Insufficient install-name header capacity')
    subprocess.run(['codesign', '--verify', '--strict', str(library)], check=True)
    return {
        'method': ('Equivalent system framework paths without Versions; '
                   'LC_ID_DYLIB rewrite; ad-hoc signature.'),
        'original_install_name': original_name,
        'install_name': name,
        'unchanged_payload_sha256': hashlib.sha256(
            original[before[0]:before[1]]).hexdigest(),
        'header_free_bytes': after[2],
        'section_layout_unchanged': True,
    }


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
