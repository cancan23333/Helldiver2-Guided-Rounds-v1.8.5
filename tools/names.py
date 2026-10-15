"""Identifier inventory: the set of names that appear in each revision, so a
typo or an accidentally renamed variable shows up as a name that only exists in
one of the two files."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from luatokens import tokenize

OLD = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.0\docs\guided_rounds.lua')
NEW = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.5\docs\guided_rounds.lua')

KEYWORDS = set('''and break do else elseif end false for function if in local nil not or
repeat return then true until while goto'''.split())


def names(path):
    toks = tokenize(path.read_text(encoding='utf-8'))
    plain, dotted = set(), set()
    for i, (kind, value) in enumerate(toks):
        if kind != 'name' or value in KEYWORDS:
            continue
        prev = toks[i - 1][1] if i else None
        if prev in ('.', ':'):
            dotted.add(value)
        else:
            plain.add(value)
    return plain, dotted


po, do_ = names(OLD)
pn, dn = names(NEW)
print('plain identifiers only in v1.8.0:', sorted(po - pn))
print('plain identifiers only in v1.8.5:', sorted(pn - po))
print('field names only in v1.8.0:', sorted(do_ - dn))
print('field names only in v1.8.5:', sorted(dn - do_))
