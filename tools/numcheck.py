"""Compare numeric literals with comments removed, so only code numbers count."""
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from luatokens import tokenize

OLD = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.0\docs\guided_rounds.lua')
NEW = pathlib.Path(r'D:\HD2自瞄\Guided-Rounds-v1.8.5\docs\guided_rounds.lua')

no = collections.Counter(v for k, v in tokenize(OLD.read_text(encoding='utf-8')) if k == 'num')
nn = collections.Counter(v for k, v in tokenize(NEW.read_text(encoding='utf-8')) if k == 'num')
print('numeric literals in code (comments dropped):')
for k in sorted(set(no) | set(nn), key=lambda s: (len(s), s)):
    mark = '' if no[k] == nn[k] else '   <-- CHANGED'
    if mark or no[k]:
        print(f'  {k:>22s}: {no[k]:4d} -> {nn[k]:4d}{mark}')

so = collections.Counter(v for k, v in tokenize(OLD.read_text(encoding='utf-8')) if k == 'str')
sn = collections.Counter(v for k, v in tokenize(NEW.read_text(encoding='utf-8')) if k == 'str')
print('\nstring literals that disappeared:')
for k in sorted(set(so) - set(sn)):
    print(f'  {k!r}  x{so[k]}')
print('\nstring literals that appeared:')
for k in sorted(set(sn) - set(so)):
    print(f'  {k!r}  x{sn[k]}')
