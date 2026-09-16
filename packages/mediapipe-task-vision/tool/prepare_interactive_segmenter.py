"""Prepare Google's official 1.0.1 task runtime for one build target.

The runtime is present in Google's Python wheels but not as a standalone public
C++ build target (MagicTouch, Proofreader and Summarizer are closed prebuilts).
No Python is shipped to apps. This tool verifies a wheel and extracts only its
native library and notices into one archive per (platform, architecture).

macOS load-command paths and the ad-hoc signature are adjusted for Dart
bundling; code/data bytes are verified unchanged. Other platforms ship the
library byte-for-byte. The tool never publishes anything.

The macOS row keeps its historical segmenter names so the published archive
stays reproducible. New targets use the `tasks-v<version>-<build>` tag and
`mediapipe-tasks-<version>-<platform>-<arch>.tar.gz` archive naming that the
core hook's release table expects.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import tarfile
import urllib.request
import zipfile

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
VERSION = '1.0.1'
BUILD = 1
PYPI = 'https://files.pythonhosted.org/packages/'
MODEL_URL = ('https://storage.googleapis.com/mediapipe-models/'
             'interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task')
MODEL_SHA256 = '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03'

# Symbols every 1.0.1 runtime must export; MagicTouch is absent on Windows.
COMMON_SYMBOLS = (
    'MpTextClassifierCreate', 'MpTextEmbedderCreate', 'MpLanguageDetectorCreate',
    'MpTextProofreaderCreate', 'MpTextSummarizerCreate', 'MpAudioClassifierCreate',
    'MpImageCreateFromFile', 'MpImageCreateFromUint8Data', 'MpImageDataFloat32',
    'MpImageGetWidth', 'MpImageGetHeight', 'MpImageGetChannels',
    'MpImageGetByteDepth', 'MpImageFree', 'MpErrorFree',
)
MAGIC_TOUCH_SYMBOLS = (
    'MpInteractiveSegmenterCreate', 'MpInteractiveSegmenterSetImage',
    'MpInteractiveSegmenterSegment', 'MpInteractiveSegmenterClose',
)

# One row per build target. `platform`/`architecture` use Dart's names and
# must equal the split of the core release table's target key.
PLATFORMS = {
    'macos/arm64': dict(
        wheel=PYPI + '18/56/911762884caba685dc8156d0136c58196a228c2b447023cfa0cfdb32f6c5/'
              'mediapipe-1.0.1-py3-none-macosx_11_0_arm64.whl',
        wheel_sha256='0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031',
        upstream_library='mediapipe/tasks/c/libmediapipe.dylib',
        library_sha256='9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a',
        library_name='libinteractive_segmenter.dylib',
        tag='interactive-segmenter-v1.0.1-1',
        archive='mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz',
        minimum_os='14.0', delegates=['cpu'], symbols=COMMON_SYMBOLS + MAGIC_TOUCH_SYMBOLS,
        scope='Full upstream runtime, exposed here only for Interactive Segmenter. '
              'GPU is not enabled: the upstream macOS stroke shader fails to initialize.',
        notes='Native library from the official MediaPipe 1.0.1 macOS wheel. '
              'System framework load paths and signing metadata are adjusted for Dart '
              'bundling; all code and data are verified unchanged. Requires macOS 14+.',
    ),
    'linux/x64': dict(
        wheel=PYPI + '2a/58/bdd5bada89d7a132375df05e962bf702c148b47043dca98d820d9395152b/'
              'mediapipe-1.0.1-py3-none-manylinux_2_28_x86_64.whl',
        wheel_sha256='121522251afc3c135e4b7b0c341dd5e050ad1ec87631127484f3c389ae385044',
        upstream_library='mediapipe/tasks/c/libmediapipe.so',
        library_sha256='b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a',
        library_name='libmediapipe.so', minimum_os='glibc 2.28', delegates=['cpu'],
        symbols=COMMON_SYMBOLS + MAGIC_TOUCH_SYMBOLS,
        scope='Full upstream runtime. GPU is not validated.',
        notes='Native library from the official MediaPipe 1.0.1 manylinux_2_28 x86_64 '
              'wheel, shipped byte-for-byte. Loads libEGL.so.1 and libGLESv2.so.2 at '
              'startup even for CPU inference; install Mesa EGL/GLES on the host.',
    ),
    'linux/arm64': dict(
        wheel=PYPI + '16/9d/515c6ebc98db21484b2b93b7403464d08fb7861b6430752801bc75d29372/'
              'mediapipe-1.0.1-py3-none-manylinux_2_28_aarch64.whl',
        wheel_sha256='d6050e773dc6698eb86324090f61af1ccab28a6f1e9f77d98fe0611cef707997',
        upstream_library='mediapipe/tasks/c/libmediapipe.so',
        library_sha256='b60afadf1a6c0bf9aae5ae2be5c66257e4e951ff0a123e86e3f6d24647854793',
        library_name='libmediapipe.so', minimum_os='glibc 2.28', delegates=['cpu'],
        symbols=COMMON_SYMBOLS + MAGIC_TOUCH_SYMBOLS,
        scope='Full upstream runtime. GPU is not validated.',
        notes='Native library from the official MediaPipe 1.0.1 manylinux_2_28 aarch64 '
              'wheel, shipped byte-for-byte. Loads libEGL.so.1 and libGLESv2.so.2 at '
              'startup even for CPU inference; install Mesa EGL/GLES on the host.',
    ),
    'windows/x64': dict(
        wheel=PYPI + '22/71/42365b0aec2a96dfbeb3441220fe8dccd9a833f36adfecf3aa9f211c449b/'
              'mediapipe-1.0.1-py3-none-win_amd64.whl',
        wheel_sha256='96dc9de6bd04a6315ef424fda5c48e0929f2d78317295e75bc32c0bceeab517b',
        upstream_library='mediapipe/tasks/c/libmediapipe.dll',
        library_sha256='31335db8bb8cd4bb294fd689b6b06086eb33782ee9c7f4667e12a6014a68436c',
        library_name='libmediapipe.dll', minimum_os='10.0', delegates=['cpu'],
        symbols=COMMON_SYMBOLS,
        scope='Full upstream runtime except MagicTouch, which Google does not ship '
              'for Windows. GPU is not available on Windows desktop builds.',
        notes='Native library from the official MediaPipe 1.0.1 win_amd64 wheel, '
              'shipped byte-for-byte. Does not export MpInteractiveSegmenterCreate.',
    ),
    'windows/arm64': dict(
        wheel=PYPI + '49/47/8a901eade7352051ae4d7b0b070ad8a84bde9cbf3092afd69088982842bb/'
              'mediapipe-1.0.1-py3-none-win_arm64.whl',
        wheel_sha256='4bbbb3838a99f7fdcd3cb0e071560120df45ddc48c1ad097ef1457f8600e0e77',
        upstream_library='mediapipe/tasks/c/libmediapipe.dll',
        library_sha256='9463e2ba64ae762eb8f9fa90f5f59cc3424a9ff86789b7f18bd3d30662286762',
        library_name='libmediapipe.dll', minimum_os='10.0', delegates=['cpu'],
        symbols=COMMON_SYMBOLS,
        scope='Full upstream runtime except MagicTouch, which Google does not ship '
              'for Windows. GPU is not available on Windows desktop builds.',
        notes='Native library from the official MediaPipe 1.0.1 win_arm64 wheel, '
              'shipped byte-for-byte. Does not export MpInteractiveSegmenterCreate.',
    ),
}
for _target, _row in PLATFORMS.items():
    _row.setdefault('tag', f'tasks-v{VERSION}-{BUILD}')
    _row.setdefault('archive', f'mediapipe-tasks-{VERSION}-{_target.replace("/", "-")}.tar.gz')

# Backwards-compatible names for the macOS row, used by reference tooling.
_MACOS = PLATFORMS['macos/arm64']
TAG = _MACOS['tag']
WHEEL_URL = _MACOS['wheel']
WHEEL_SHA256 = _MACOS['wheel_sha256']
LIBRARY_SHA256 = _MACOS['library_sha256']
LIBRARY_NAME = _MACOS['library_name']
ARCHIVE_NAME = _MACOS['archive']

ELF_MACHINES = {'x64': 62, 'arm64': 183}
PE_MACHINES = {'x64': 0x8664, 'arm64': 0xAA64}
LINUX_SYSTEM_LIBRARIES = re.compile(
    r'^(libc|libm|libdl|libpthread|librt|libgcc_s|libstdc\+\+|ld-linux-[a-z0-9-]+'
    r'|libEGL|libGLESv2)\.so(\.\d+)*$')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def elf_info(data):
    """Machine, SONAME and NEEDED entries of a 64-bit little-endian ELF."""
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        raise ValueError('Expected a 64-bit little-endian ELF library')
    machine = struct.unpack_from('<H', data, 18)[0]
    shoff = struct.unpack_from('<Q', data, 0x28)[0]
    shentsize, shnum = struct.unpack_from('<HH', data, 0x3a)
    sections = []
    for index in range(shnum):
        offset = shoff + index * shentsize
        _, kind, _, _, off, size, link, _, _, _ = struct.unpack_from('<IIQQQQIIQQ', data, offset)
        sections.append((kind, off, size, link))
    soname, needed, symbols = None, [], set()
    for kind, off, size, link in sections:
        strings = sections[link][1] if kind in (6, 11) else None
        if kind == 6:  # .dynamic
            for entry in range(size // 16):
                tag, value = struct.unpack_from('<qQ', data, off + entry * 16)
                if tag == 0:
                    break
                if tag in (1, 14):  # DT_NEEDED, DT_SONAME
                    name = data[strings + value:data.index(b'\0', strings + value)].decode()
                    if tag == 1:
                        needed.append(name)
                    else:
                        soname = name
        elif kind == 11:  # .dynsym
            for entry in range(size // 24):
                name, info, _, shndx, _, _ = struct.unpack_from('<IBBHQQ', data, off + entry * 24)
                if shndx != 0 and (info >> 4) in (1, 2):
                    symbols.add(data[strings + name:data.index(b'\0', strings + name)].decode())
    return machine, soname, needed, symbols


def pe_info(data):
    """Machine, imported DLLs and exported names of a PE32+ library."""
    header = struct.unpack_from('<I', data, 0x3c)[0]
    if data[header:header + 4] != b'PE\0\0':
        raise ValueError('Expected a PE library')
    machine = struct.unpack_from('<H', data, header + 4)[0]
    section_count = struct.unpack_from('<H', data, header + 6)[0]
    optional_size = struct.unpack_from('<H', data, header + 20)[0]
    optional = header + 24
    if struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise ValueError('Expected a PE32+ library')
    directories = optional + 112
    sections = []
    for index in range(section_count):
        offset = optional + optional_size + index * 40
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from('<IIII', data, offset + 8)
        sections.append((virtual_address, max(virtual_size, raw_size), raw_pointer))

    def to_offset(rva):
        for address, size, pointer in sections:
            if address <= rva < address + size:
                return rva - address + pointer
        raise ValueError(f'Unmapped RVA {rva:#x}')

    def string_at(rva):
        offset = to_offset(rva)
        return data[offset:data.index(b'\0', offset)].decode()

    exports = set()
    export_rva = struct.unpack_from('<I', data, directories)[0]
    if export_rva:
        table = to_offset(export_rva)
        count, names_rva = struct.unpack_from('<I', data, table + 24)[0], struct.unpack_from('<I', data, table + 32)[0]
        names = to_offset(names_rva)
        exports = {string_at(struct.unpack_from('<I', data, names + 4 * i)[0]) for i in range(count)}
    imports = []
    import_rva = struct.unpack_from('<I', data, directories + 8)[0]
    if import_rva:
        entry = to_offset(import_rva)
        while True:
            name_rva = struct.unpack_from('<I', data, entry + 12)[0]
            if not name_rva:
                break
            imports.append(string_at(name_rva))
            entry += 20
    return machine, imports, exports


def check_library(target, row, library):
    """Confirm architecture, exports and system-only dependencies."""
    platform, architecture = target.split('/')
    data = library.read_bytes()
    if platform == 'macos':
        build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(library)], text=True)
        arch = subprocess.check_output(['xcrun', 'lipo', '-archs', str(library)], text=True).strip()
        minimum = row['minimum_os']
        if ('platform MACOS' not in build or arch != architecture or
                not re.search(rf'^\s*minos {re.escape(minimum)}\s*$', build, re.MULTILINE)):
            raise ValueError(f'Expected macOS {architecture} native library with minimum OS {minimum}')
        symbols = {name.removeprefix('_') for name in subprocess.check_output(
            ['nm', '-gjU', str(library)], text=True).splitlines()}
        dependencies = subprocess.check_output(['otool', '-L', str(library)], text=True)
        for line in dependencies.splitlines()[2:]:
            if not line.strip().startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError(f'Non-system dependency: {line}')
    elif platform == 'linux':
        machine, soname, needed, symbols = elf_info(data)
        if machine != ELF_MACHINES[architecture]:
            raise ValueError(f'Expected an ELF {architecture} library, found machine {machine}')
        if soname != row['library_name']:
            raise ValueError(f'Unexpected SONAME {soname}')
        for name in needed:
            if not LINUX_SYSTEM_LIBRARIES.match(name):
                raise ValueError(f'Non-system dependency: {name}')
        symbols = {name.split('@')[0] for name in symbols}
    elif platform == 'windows':
        machine, imports, symbols = pe_info(data)
        if machine != PE_MACHINES[architecture]:
            raise ValueError(f'Expected a PE {architecture} library, found machine {machine:#x}')
        for name in imports:
            lower = name.lower()
            if not (lower.startswith('api-ms-win-') or lower in {
                    'kernel32.dll', 'ntdll.dll', 'advapi32.dll', 'user32.dll', 'wininet.dll',
                    'bcrypt.dll', 'bcryptprimitives.dll', 'dbghelp.dll', 'ws2_32.dll',
                    'shell32.dll', 'ole32.dll', 'shlwapi.dll', 'crypt32.dll',
                    'sspicli.dll', 'secur32.dll', 'iphlpapi.dll', 'msvcrt.dll', 'ucrtbase.dll'}):
                raise ValueError(f'Non-system dependency: {name}')
    else:
        raise ValueError(f'Unknown platform {platform}')
    for name in row['symbols']:
        if name not in symbols:
            raise ValueError(f'Missing native symbol: {name}')


def prepare(target, wheel, output):
    row = PLATFORMS[target]
    platform, architecture = target.split('/')
    if digest(wheel.read_bytes()) != row['wheel_sha256']:
        raise ValueError('Official wheel checksum mismatch')
    with zipfile.ZipFile(wheel) as source:
        files = {
            row['library_name']: source.read(row['upstream_library']),
            'LICENSE': source.read(f'mediapipe-{VERSION}.dist-info/licenses/LICENSE'),
            'NOTICE': source.read(f'mediapipe-{VERSION}.dist-info/licenses/NOTICE'),
        }
    if digest(files[row['library_name']]) != row['library_sha256']:
        raise ValueError('Official library checksum mismatch')
    output.mkdir(parents=True, exist_ok=True)
    library = output / row['library_name']
    library.write_bytes(files[row['library_name']])
    manifest = {
        'origin': 'official-pypi-wheel', 'upstream_version': VERSION,
        'upstream_url': row['wheel'], 'upstream_sha256': row['wheel_sha256'],
        'upstream_library': row['upstream_library'],
        'upstream_library_sha256': row['library_sha256'],
        'release': row['tag'], 'platform': platform, 'architecture': architecture,
        'minimum_os': row['minimum_os'], 'delegates': row['delegates'],
    }
    if platform == 'macos':
        from macho_metadata import normalize
        packaging = normalize(library)
        files[row['library_name']] = library.read_bytes()
    else:
        packaging = None
    artifact_hash = digest(files[row['library_name']])
    manifest.update({
        'sha256': artifact_hash, 'bytes': len(files[row['library_name']]),
        'files': {name: digest(data) for name, data in files.items()},
    })
    if packaging is not None:
        manifest['packaging'] = packaging
    manifest['scope'] = row['scope']
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    for name, data in files.items():
        (output / name).write_bytes(data)
    check_library(target, row, output / row['library_name'])
    release = PACKAGE / 'build/releases' / row['tag']
    release.mkdir(parents=True, exist_ok=True)
    archive = release / row['archive']
    with archive.open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as bundle:
                for name, data in sorted(files.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mode = 0o644
                    bundle.addfile(entry, io.BytesIO(data))
    checksum = digest(archive.read_bytes())
    (release / f'manifest-{platform}-{architecture}.json').write_bytes(files['manifest.json'])
    sums = release / 'SHA256SUMS'
    lines = [line for line in (sums.read_text().splitlines() if sums.exists() else [])
             if not line.endswith(f'  {row["archive"]}')]
    sums.write_text('\n'.join(sorted([*lines, f'{checksum}  {row["archive"]}'])) + '\n')
    notes = release / 'RELEASE_NOTES.md'
    section = (f'## {row["archive"]}\n\nMediaPipe {VERSION} task runtime for {platform} '
               f'{architecture}, {", ".join(row["delegates"]).upper()} only.\n\n{row["notes"]} '
               'Includes its complete LICENSE and NOTICE. This is the full upstream runtime, '
               'not a standalone source build. Models are separate. No Python is required '
               f'by apps.\n\nArchive SHA-256: `{checksum}`\n\nLibrary SHA-256: `{artifact_hash}`\n')
    existing = notes.read_text() if notes.exists() else ''
    existing = re.sub(rf'## {re.escape(row["archive"])}\n.*?(?=\n## |\Z)', '', existing, flags=re.DOTALL)
    notes.write_text((existing.rstrip() + '\n\n' if existing.strip() else '') + section)
    if target == 'macos/arm64':
        # The published macOS release predates multi-platform notes; keep its files.
        (release / 'manifest.json').write_bytes(files['manifest.json'])
    print(json.dumps({'target': target, 'archive': str(archive), 'sha256': checksum,
                      'bytes': archive.stat().st_size, 'manifest': manifest}, indent=2))


def fetch_wheel(target, destination):
    row = PLATFORMS[target]
    if destination.exists() and digest(destination.read_bytes()) == row['wheel_sha256']:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(row['wheel'], timeout=300) as response:
        data = response.read()
    if digest(data) != row['wheel_sha256']:
        raise ValueError('Downloaded wheel checksum mismatch')
    destination.write_bytes(data)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--target', choices=sorted(PLATFORMS), default='macos/arm64',
                        help='Build target to package (default: macos/arm64)')
    parser.add_argument('--wheel', type=Path, help='Already-downloaded official wheel')
    parser.add_argument('--output', type=Path,
                        help='Extraction directory (default: build/native/tasks-runtime/<target>)')
    args = parser.parse_args()
    row = PLATFORMS[args.target]
    default_wheel = (REPO / 'build/codex-tmp/mediapipe-1.0.1-macos-arm64.whl'
                     if args.target == 'macos/arm64'
                     else REPO / 'build/wheels' / row['wheel'].rsplit('/', 1)[-1])
    wheel = fetch_wheel(args.target, args.wheel or default_wheel)
    output = args.output or (PACKAGE / 'build/native/interactive_segmenter'
                             if args.target == 'macos/arm64'
                             else PACKAGE / 'build/native/tasks-runtime' / args.target)
    prepare(args.target, wheel, output)


if __name__ == '__main__':
    main()
