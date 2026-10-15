"""Catch the bug class that broke v1.8.1 on the first try:

a chunk-level `local` that is READ before the line that declares it.  Lua
resolves such a name as a GLOBAL, so it is nil at run time - even after the
`local` line has executed, because the binding was decided when the function
was compiled.  This is exactly how `set_lease` / `sync_leases` were dead in
v1.8.0 (F10) and how `ptr_ok` was dead in the first v1.8.1 build.

Usage:  python guardglobals.py <lua-file> [more files...]
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from luatokens import tokenize                     # noqa: E402

KEYWORDS = set('''and break do else elseif end false for function if in local nil not or
repeat return then true until while goto'''.split())


def tokenize_lines(src):
    """(kind, value, line) - lines recovered by re-walking the source."""
    out, line = [], 1
    for kind, value in tokenize(src):
        out.append((kind, value, line))
        line += src.count('\n') if False else 0
    return out


def scan(path):
    src = pathlib.Path(path).read_text(encoding='utf-8')
    lines = src.split('\n')
    toks = []                                       # (kind, value, line)
    # tokenize line by line: no token in this file spans a line
    for i, line in enumerate(lines, 1):
        for kind, value in tokenize(line):
            toks.append((kind, value, i))

    # chunk-level locals: the file's style puts every one of them at column 0
    declared = {}                                   # name -> line
    for i, line in enumerate(lines, 1):
        m = re.match(r'^local\s+(function\s+)?(.+)$', line)
        if not m:
            continue
        if m.group(1):
            name = re.match(r'([A-Za-z_]\w*)', m.group(2).strip())
            if name:
                declared.setdefault(name.group(1), i)
            continue
        names = m.group(2).split('=')[0]
        for raw in names.split(','):
            name = raw.strip()
            if re.fullmatch(r'[A-Za-z_]\w*', name):
                declared.setdefault(name, i)

    findings = []
    for idx, (kind, value, line) in enumerate(toks):
        if kind != 'name' or value in KEYWORDS:
            continue
        prev = toks[idx - 1][1] if idx else None
        if prev in ('.', ':'):
            continue                                # a field, not a name
        if prev in ('local', 'function', 'goto'):
            continue                                # a declaration
        nxt = toks[idx + 1][1] if idx + 1 < len(toks) else None
        if nxt == '=':
            continue                                # an assignment target or a
                                                    # table field key, not a read
        decl = declared.get(value)
        if decl is not None and line < decl:
            findings.append((value, line, decl, lines[line - 1].strip()[:90]))
    return findings, len(declared)


def main(paths):
    total = 0
    for path in paths:
        findings, n = scan(path)
        print(f'=== {path}  ({n} chunk-level locals) ===')
        seen = set()
        for name, line, decl, text in findings:
            key = (name, line)
            if key in seen:
                continue
            seen.add(key)
            total += 1
            print(f'  {name:16s} read at line {line:5d} but declared at {decl:5d}'
                  f'   | {text}')
        if not findings:
            print('  no use-before-declaration found')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
