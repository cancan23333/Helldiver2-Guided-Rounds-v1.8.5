"""Compact view of the token diff: one line per hunk, removed -> added."""
import difflib
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from luatokens import tokenize

OLD = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.0\docs\guided_rounds.lua')
NEW = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.5\docs\guided_rounds.lua')

BYTES = r"string\.char\((?:0x[0-9A-Fa-f]{1,2},\s*){7}0x[0-9A-Fa-f]{1,2}\)"
HEXHASH = r"hash8\('0x[0-9A-Fa-f]{1,16}'\)"


def normalise(src):
    return re.sub(HEXHASH, 'HASH8', re.sub(BYTES, 'HASH8', src))


def show(toks):
    return ' '.join(v for _, v in toks)


def main():
    old = tokenize(normalise(OLD.read_text(encoding='utf-8')))
    new = tokenize(normalise(NEW.read_text(encoding='utf-8')))
    sm = difflib.SequenceMatcher(None, [v for _, v in old], [v for _, v in new], autojunk=False)
    n = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        n += 1
        print(f'--- hunk {n} [{tag}] old#{i1}-{i2} new#{j1}-{j2}')
        print(f'  - {show(old[i1:i2])[:600]}')
        print(f'  + {show(new[j1:j2])[:600]}')
    print(f'total hunks: {n}')


if __name__ == '__main__':
    main()
