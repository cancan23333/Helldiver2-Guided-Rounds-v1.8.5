import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
try:
    from luaparser import ast, astnodes
except ImportError:
    print('locals.py needs luaparser:  python -m pip install luaparser')
    raise SystemExit(2)

path = pathlib.Path(sys.argv[1])
src = path.read_text(encoding='utf-8')
tree = ast.parse(src)

CHUNK = astnodes.Chunk
FUNC = (astnodes.Function, astnodes.LocalFunction, astnodes.AnonymousFunction,
        astnodes.Method)

count = {'local': 0, 'local_function': 0, 'param': 0, 'loopvar': 0}
names = []

def visit(node):
    if isinstance(node, astnodes.LocalAssign):
        for t in node.targets:
            if isinstance(t, astnodes.Name):
                count['local'] += 1
                names.append((t.display_name, node.line if hasattr(node, 'line') else '?'))
    elif isinstance(node, astnodes.LocalFunction):
        count['local_function'] += 1
        if isinstance(node.name, astnodes.Name):
            names.append((node.name.display_name, 'fn'))
    elif isinstance(node, astnodes.Fornum):
        for t in node.targets:
            count['loopvar'] += 1
            names.append((t.display_name, 'fornum'))
    elif isinstance(node, astnodes.Forin):
        for t in node.targets:
            count['loopvar'] += 1
            names.append((t.display_name, 'forin'))
    elif isinstance(node, FUNC):
        # parameters belong to this prototype; do not descend into the body
        for a in node.args:
            if isinstance(a, astnodes.Name):
                count['param'] += 1
        return
    for child in node.body if hasattr(node, 'body') else []:
        pass
    for child in ast.iter_child_nodes(node) if hasattr(ast, 'iter_child_nodes') else []:
        visit(child)

def _kids(node):
    out = []
    for child in node.__dict__.values():
        if isinstance(child, astnodes.Node):
            out.append(child)
        elif isinstance(child, (list, tuple)):
            for item in child:
                if isinstance(item, astnodes.Node):
                    out.append(item)
    return out

# simpler: iterate all nodes but stop at function boundaries
stack = [tree]
while stack:
    node = stack.pop()
    if isinstance(node, astnodes.LocalFunction):
        count['local_function'] += 1
        if isinstance(node.name, astnodes.Name):
            names.append(node.name.display_name)
        continue
    if isinstance(node, FUNC):
        # a nested prototype: its parameters and locals are NOT chunk slots
        continue
    if isinstance(node, astnodes.LocalAssign):
        for t in node.targets:
            if isinstance(t, astnodes.Name):
                count['local'] += 1
                names.append(t.display_name)
    elif isinstance(node, astnodes.Fornum):
        count['loopvar'] += 1
        names.append(node.target.display_name if isinstance(node.target, astnodes.Name) else '?')
    elif isinstance(node, astnodes.Forin):
        for t in node.targets:
            count['loopvar'] += 1
            names.append(t.display_name)
    for child in node.__dict__.values():
        if isinstance(child, astnodes.Node):
            stack.append(child)
        elif isinstance(child, (list, tuple)):
            for item in child:
                if isinstance(item, astnodes.Node):
                    stack.append(item)

total = sum(count.values())
print('main-chunk local slots (Lua 5.1 counts all decls in the prototype):')
for k, v in count.items():
    print(f'  {k:16s} {v}')
print('  TOTAL           ', total)
print('  remaining to 200:', 200 - total)
