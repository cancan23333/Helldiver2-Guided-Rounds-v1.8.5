"""Verification for the v1.8.0 -> v1.8.2 refactor.

1. Syntax check both revisions (needs luaparser: pip install luaparser; skipped
   with a note when it is not installed - the token diff below needs nothing).
2. Normalise the two hash notations, then diff the token streams: every semantic
   edit shows up as a hunk.
3. Compare the multiset of numeric literals, so an accidentally changed engine
   offset or magic value cannot hide inside the diff noise.
"""
import collections
import difflib
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from luatokens import tokenize                               # noqa: E402

try:
    from luaparser import ast                                # noqa: E402
except ImportError:                                          # pragma: no cover
    ast = None

OLD = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.0\docs\guided_rounds.lua')
NEW = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.5\docs\guided_rounds.lua')

BYTES = r"string\.char\((?:0x[0-9A-Fa-f]{1,2},\s*){7}0x[0-9A-Fa-f]{1,2}\)"
HEXHASH = r"hash8\('0x[0-9A-Fa-f]{1,16}'\)"


def normalise(src):
    src = re.sub(BYTES, 'HASH8', src)
    src = re.sub(HEXHASH, 'HASH8', src)
    return src


def numbers(src):
    return collections.Counter(m.group(0) for m in re.finditer(
        r'(?<![\w.])0[xX][0-9A-Fa-f]+|(?<![\w.])\d+\.?\d*(?:[eE][-+]?\d+)?', src))


def main():
    old_raw, new_raw = OLD.read_text(encoding='utf-8'), NEW.read_text(encoding='utf-8')
    for name, src in (('v1.8.0', old_raw), ('v1.8.2', new_raw)):
        if ast is None:
            print(f'{name}: {src.count(chr(10))} lines (install luaparser for the AST check)')
            continue
        tree = ast.parse(src)
        n = sum(1 for _ in ast.walk(tree))
        print(f'{name}: parses clean, {n} AST nodes, {src.count(chr(10))} lines')

    old, new = normalise(old_raw), normalise(new_raw)
    ta = tokenize(old)
    tb = tokenize(new)
    print(f'\ntokens old={len(ta)} new={len(tb)}')

    sa = [f'{k}\x01{v}' for k, v in ta]
    sb = [f'{k}\x01{v}' for k, v in tb]
    diff = list(difflib.unified_diff(sa, sb, 'v1.8.0', 'v1.8.2', n=3, lineterm=''))
    hunks = [d for d in diff if d.startswith('@@')]
    print(f'token hunks: {len(hunks)}')
    for d in diff:
        print('  ' + d.replace('\x01', ' '))

    no, nn = numbers(old), numbers(new)
    keys = sorted(set(no) | set(nn), key=lambda k: (k.lower(), k))
    print('\nnumeric literal inventory changes:')
    changed = False
    for k in keys:
        if no[k] != nn[k]:
            changed = True
            print(f'  {k:>12s}: {no[k]} -> {nn[k]}')
    if not changed:
        print('  (identical)')


if __name__ == '__main__':
    main()
