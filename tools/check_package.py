"""Independent check of the built installer package.

Reads Guided-Rounds-v1.8.5.zip with nothing but struct/zipfile and re-derives the
Lua resource from the archive, then compares it with docs/guided_rounds.lua and
with the v1.8.0 package layout."""
import hashlib
import json
import pathlib
import struct
import sys
import zipfile

ROOT = pathlib.Path(r'D:\HD2自瞄')
PKG = ROOT / 'Guided-Rounds-v1.8.5.zip'
OLD = ROOT / 'Guided-Rounds-v1.8.0'
SRC = ROOT / 'Guided-Rounds-v1.8.5' / 'docs' / 'guided_rounds.lua'
RESOURCE = 'mods/cancan2333/guided_rounds'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
MIX = 0xC6A4A7935BD1E995
MASK = (1 << 64) - 1


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


def read_archive(blob):
    magic, types, files = struct.unpack_from('<III', blob, 0)
    assert magic == 0xF0000011, hex(magic)
    out = {}
    for i in range(files):
        row = struct.unpack_from('<7Q6I', blob, 72 + 32 * types + 80 * i)
        name_hash, kind, offset, _, _, _, _, length = row[:8]
        out[name_hash] = (kind, blob[offset:offset + length])
    total = struct.unpack_from('<Q', blob, 32)[0]
    assert total == len(blob), (total, len(blob))
    return out, types, files


ok = True


def check(label, condition, detail=''):
    global ok
    ok = ok and bool(condition)
    print(f'  [{"ok " if condition else "FAIL"}] {label}{("  " + detail) if detail else ""}')


print('package:', PKG.name, PKG.stat().st_size, 'bytes')
with zipfile.ZipFile(PKG) as package:
    names = sorted(package.namelist())
    print('  entries:', ', '.join(names))
    manifest = json.loads(package.read('manifest.json').decode('utf-8'))
    old_manifest = json.loads((OLD / 'manifest.json').read_text(encoding='utf-8'))
    archive = package.read('Addon/' + ARCHIVE)
    stream = package.read('Addon/' + ARCHIVE + '.stream')
    gpu = package.read('Addon/' + ARCHIVE + '.gpu_resources')

print('\nmanifest')
check('same GUID as v1.8.0 (upgrade, not a new mod)',
      manifest['Guid'] == old_manifest['Guid'], manifest['Guid'])
check('Version is a string and bumped like v1.8.0',
      isinstance(manifest['Version'], str)
      and type(manifest['Version']) is type(old_manifest['Version'])
      and manifest['Version'] == '1.8.5', repr(manifest['Version']))
check('name bumped', manifest['Name'] == 'Guided Rounds v1.8.5', manifest['Name'])
check('option includes Addon',
      manifest['Options'][0]['Include'] == old_manifest['Options'][0]['Include'])
check('option keys match v1.8.0',
      sorted(manifest['Options'][0]) == sorted(old_manifest['Options'][0]))
check('top-level keys match v1.8.0', sorted(manifest) == sorted(old_manifest))

print('\narchive')
resources, types, files = read_archive(archive)
check('one Lua resource', (types, files) == (1, 1))
key = resource_hash(RESOURCE)
check('resource hash present', key in resources, hex(key))
kind, payload = resources[key]
check('resource type is Lua', kind == 0xA14E8DFA2CD117E2, hex(kind))
body_len, version = struct.unpack_from('<II', payload, 0)
check('envelope version 2', version == 2)
check('envelope length matches', body_len == len(payload) - 8, f'{body_len} vs {len(payload) - 8}')
body = payload[8:]
check('sidecars empty', stream == b'' and gpu == b'')

print('\npayload')
src = SRC.read_bytes()
check('declaration is the first line',
      body.startswith(b'-- HD2-Addon: ' + RESOURCE.encode() + b'\n'))
check('payload equals docs/guided_rounds.lua', body == src,
      hashlib.sha256(body).hexdigest()[:16] + ' vs ' + hashlib.sha256(src).hexdigest()[:16])
check('plaintext UTF-8, no BOM/NUL', b'\0' not in body and not body.startswith(b'\xef\xbb\xbf'))
check('declaration line fits the 256 byte discovery limit',
      len(b'-- HD2-Addon: ' + RESOURCE.encode() + b'\n') <= 256)

print('\nagainst the v1.8.0 package')
old_blob = (OLD / 'Addon' / ARCHIVE).read_bytes()
old_res, old_types, old_files = read_archive(old_blob)
check('same archive header shape', (old_types, old_files) == (types, files))
check('same resource hash', set(old_res) == set(resources))
old_kind, old_payload = old_res[key]
check('same entry kind and envelope version',
      old_kind == kind and old_payload[4:8] == payload[4:8])
check('source size in the same ballpark as v1.8.0',
      abs(len(body) - (len(old_payload) - 8)) < 0.05 * (len(old_payload) - 8),
      f'{len(old_payload) - 8} -> {len(body)}')

print('\nRESULT:', 'ALL CHECKS PASSED' if ok else 'FAILURES PRESENT')
sys.exit(0 if ok else 1)
