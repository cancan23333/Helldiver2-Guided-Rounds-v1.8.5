"""Minimal Lua 5.1 tokenizer used to diff two revisions of a source file.

Comments and whitespace are dropped, so a token diff shows exactly the semantic
edits - which is what a refactor review needs. Long strings/comments and both
quote styles are handled; numbers keep their original spelling."""
import re, sys, pathlib

NAME = re.compile(r'[A-Za-z_]\w*')
NUM = re.compile(r'0[xX][0-9A-Fa-f]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?')

OPEN_LONG = re.compile(r'\[(=*)\[')


def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in ' \t\r\n\f\v':
            i += 1
            continue
        if src.startswith('--', i):
            j = i + 2
            m = OPEN_LONG.match(src, j)
            if m:
                close = ']' + m.group(1) + ']'
                k = src.find(close, m.end())
                i = n if k < 0 else k + len(close)
            else:
                k = src.find('\n', i)
                i = n if k < 0 else k
            continue
        m = OPEN_LONG.match(src, i)
        if m:
            close = ']' + m.group(1) + ']'
            k = src.find(close, m.end())
            body = src[m.end():k if k >= 0 else n]
            toks.append(('str', body))
            i = n if k < 0 else k + len(close)
            continue
        if c in '"\'':
            j, buf = i + 1, []
            while j < n:
                if src[j] == '\\':
                    buf.append(src[j:j + 2])
                    j += 2
                    continue
                if src[j] == c:
                    break
                if src[j] == '\n':
                    break
                buf.append(src[j])
                j += 1
            toks.append(('str', ''.join(buf)))
            i = j + 1
            continue
        m = NUM.match(src, i)
        if m and (c.isdigit() or (c == '.' and m.group(0)[0] == '.')):
            toks.append(('num', m.group(0)))
            i = m.end()
            continue
        m = NAME.match(src, i)
        if m:
            toks.append(('name', m.group(0)))
            i = m.end()
            continue
        for op in ('...', '..', '::', '==', '~=', '<=', '>=', '//', '<<', '>>'):
            if src.startswith(op, i):
                toks.append(('op', op))
                i += len(op)
                break
        else:
            toks.append(('op', c))
            i += 1
    return toks


def main(a, b):
    ta = tokenize(pathlib.Path(a).read_text(encoding='utf-8'))
    tb = tokenize(pathlib.Path(b).read_text(encoding='utf-8'))
    print(f'old tokens: {len(ta)}   new tokens: {len(tb)}')
    import difflib
    sa = [f'{k}\x01{v}' for k, v in ta]
    sb = [f'{k}\x01{v}' for k, v in tb]
    out = list(difflib.unified_diff(sa, sb, 'v1.8.0', 'v1.8.1', n=2, lineterm=''))
    hunks = sum(1 for d in out if d.startswith('@@'))
    print(f'hunks: {hunks}')
    for d in out:
        print(d.replace('\x01', ' '))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
