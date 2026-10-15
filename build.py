"""Build Guided-Rounds-v1.8.1: the STINGRAY Lua archive and the installer ZIP.

The mod is a Bingus Shared Loader "addon": the Lua source in docs/ is packed as
the game resource mods/cancan2333/guided_rounds inside a patch archive, and the
installer ZIP carries that archive under Addon/ next to a manifest.json.

The archive writer below is the format BingusSharedLoader/scripts/archive.py and
build_addon.py produce; build.py reproduces their output byte for byte (see
--check-against), so the package can be rebuilt without any external tooling.

    python build.py                       build Addon/ and Guided-Rounds-v1.8.1.zip
    python build.py --check-against DIR   also diff against the reference builder
"""
import argparse
import hashlib
import json
import pathlib
import struct
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
WORKSPACE = ROOT.parent

RESOURCE = 'mods/cancan2333/guided_rounds'
GUID = 'adb1ed64-ac71-5476-8acb-9909042fca85'
DISPLAY_NAME = 'Guided Rounds v1.8.5'
SOURCE = ROOT / 'docs' / 'guided_rounds.lua'
MANIFEST = ROOT / 'manifest.json'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
LUA_TYPE = 0xA14E8DFA2CD117E2
MIX = 0xC6A4A7935BD1E995
MASK = (1 << 64) - 1
PACKAGE = WORKSPACE / (DISPLAY_NAME.replace(' ', '-') + '.zip')

DESCRIPTION = (
    '把 P-92 法令手枪的原版制导移植到武器清单里的每一把枪上：弹丸出膛后自动追踪敌人，'
    '伤害和初速保持武器原本的数值。带索敌范围圆环、目标锁定标记与方框，'
    '全部参数可在游戏内 MODS 菜单实时调整。需要 Bingus Shared Loader v15+ 与 HD2Runtime。'
    'v1.8.1 是代码健壮性与可读性优化（玩法与 v1.8.0 一致，另修掉四处会报错的隐患）；'
    'v1.8.2 修掉锁定目标方框在切换武器后残留的问题。'
    '  |  Guided rounds ported from the P-92 Warrant to every weapon on the list, '
    'with an aim-cone range ring, a lock marker and a target box, all tunable from '
    'the in-game MODS tab. Requires Bingus Shared Loader v15+ and HD2Runtime. '
    'v1.8.1 is a robustness and readability pass (gameplay unchanged from v1.8.0, '
    'plus four latent crash fixes); v1.8.2 fixes the lock target box that stayed '
    'on screen after a weapon switch.')


def resource_hash(name):
    data = name.encode('utf-8')
    value = len(data) * MIX & MASK
    end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack('<Q', data[:end]):
        word = word * MIX & MASK
        word ^= word >> 47
        value = (value ^ (word * MIX & MASK)) * MIX & MASK
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], 'little')) * MIX & MASK
    value ^= value >> 47
    value = value * MIX & MASK
    return value ^ (value >> 47)


def entry_source(name, source):
    """Plain-text UTF-8 Lua with the discovery declaration as the FIRST line."""
    marker = ('-- HD2-Addon: ' + name + '\n').encode('utf-8')
    if source.startswith(b'\xef\xbb\xbf') or b'\0' in source:
        raise SystemExit('the entry must be plaintext UTF-8 without a BOM')
    source.decode('utf-8')
    if source.startswith(b'-- HD2-Addon:'):
        line, separator, remainder = source.partition(b'\n')
        if not separator or line.rstrip(b'\r') != marker[:-1]:
            raise SystemExit('the existing declaration does not match ' + name)
        source = remainder
    return marker + source


def make_archive(resources):
    """One-type (Lua) STINGRAY patch archive: {name hash: payload}."""
    count = len(resources)
    offset = (104 + 80 * count + 15) & ~15
    entries, body = bytearray(), bytearray(offset)
    for index, (name_hash, resource) in enumerate(sorted(resources.items())):
        entries += struct.pack('<7Q6I', name_hash, LUA_TYPE, offset, 0, 0, 0, 0,
                               len(resource), 0, 0, 16, 16, index)
        body += resource
        body += b'\0' * (-len(body) % 16)
        offset = len(body)
    header = struct.pack('<III20sQQ24s', 0xF0000011, 1, count, b'', offset, 0, b'')
    types = struct.pack('<IIQIIII', 0, 0, LUA_TYPE, count, 0, 16, 16)
    body[:104 + len(entries)] = header + types + entries
    return bytes(body)


def build_archive(source_bytes):
    body = entry_source(RESOURCE, source_bytes)
    resource = struct.pack('<II', len(body), 2) + body
    return make_archive({resource_hash(RESOURCE): resource})


def sha256(data):
    return hashlib.sha256(data).hexdigest().upper()


def zip_bytes(archive):
    # the manifest goes in exactly as it sits on disk, so what the manager reads
    # is byte for byte the file that was reviewed
    files = {
        'manifest.json': MANIFEST.read_bytes(),
        'Addon/' + ARCHIVE: archive,
        'Addon/' + ARCHIVE + '.stream': b'',
        'Addon/' + ARCHIVE + '.gpu_resources': b'',
    }
    return files


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check-against', metavar='DIR',
                        help='a BingusSharedLoader source checkout to verify the writer against')
    args = parser.parse_args(argv)

    source = SOURCE.read_bytes()
    archive = build_archive(source)
    print(f'source   {SOURCE}  ({len(source)} bytes, sha256 {sha256(source)})')
    print(f'archive  {ARCHIVE}  ({len(archive)} bytes, sha256 {sha256(archive)})')

    (ROOT / 'Addon').mkdir(parents=True, exist_ok=True)
    (ROOT / 'Addon' / ARCHIVE).write_bytes(archive)
    (ROOT / 'Addon' / (ARCHIVE + '.stream')).write_bytes(b'')
    (ROOT / 'Addon' / (ARCHIVE + '.gpu_resources')).write_bytes(b'')

    if args.check_against:
        checkout = pathlib.Path(args.check_against)
        sys.path.insert(0, str(checkout / 'scripts'))
        from archive import make_archive as ref_archive, resource_hash as ref_hash  # noqa: E402
        ref_body = entry_source(RESOURCE, source)
        ref_resource = struct.pack('<II', len(ref_body), 2) + ref_body
        reference = ref_archive({ref_hash(RESOURCE): ref_resource})
        print('reference builder output identical:', reference == archive)
        if reference != archive:
            raise SystemExit('the archive does not match the reference builder')

    files = zip_bytes(archive)
    files['docs/README.md'] = (ROOT / 'docs' / 'README.md').read_bytes()
    files['docs/OPTIMIZATION.md'] = (ROOT / 'docs' / 'OPTIMIZATION.md').read_bytes()
    files['docs/guided_rounds.lua'] = source
    with zipfile.ZipFile(PACKAGE, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, data)
    print(f'package  {PACKAGE}  ({PACKAGE.stat().st_size} bytes, sha256 {sha256(PACKAGE.read_bytes())})')
    print('entries  ' + ', '.join(sorted(files)))


if __name__ == '__main__':
    main()
