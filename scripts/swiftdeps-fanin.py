#!/usr/bin/env python3
"""Which files make many others compile again.

After a change to what a file declares (a new function, even a private one,
or a new case or property), the compiler rebuilds every file that used
anything that file declares, not only the new thing. So a file that declares
a type the whole app uses (`Block`, `BlockAnimation`) is expensive to touch,
and one only a few screens use is cheap.

This reads the dependency records the compiler leaves next to each object
(`.swiftdeps`, turned into text by `swift-dependency-tool --to-yaml`) and
prints, for each source file, how many other files depend on something it
declares: the number of files an update touching its declarations rebuilds.

usage: swiftdeps-fanin.py SOURCES_ROOT FILE.yaml...
"""

import collections
import os
import re
import sys

FIELD = re.compile(r'^\s*(?:- )?(kind|aspect|context|name|fingerprint|isProvides):\s*(.*)$')


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return bytes(value[1:-1], 'utf-8').decode('unicode_escape')
    return value


def nodes(path):
    """The nodes of one swiftdeps file, as dicts of the fields above."""
    node = None
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if re.match(r'^\s*- key:', line):
                if node:
                    yield node
                node = {}
                continue
            m = FIELD.match(line)
            if m and node is not None:
                node[m.group(1)] = unquote(m.group(2))
    if node:
        yield node


def readable(kind, context, name):
    """`Block`, `Block.animation`, `members of Block`: what a key names."""
    standard = {'Sa': 'Array', 'SD': 'Dictionary', 'Sh': 'Set', 'SS': 'String', 'Si': 'Int',
                'Sd': 'Double', 'Sf': 'Float', 'Sb': 'Bool', 'Su': 'UInt', 'Sq': 'Optional',
                'SJ': 'Character', 'Sr': 'UnsafeMutableBufferPointer', 'SR': 'UnsafeBufferPointer'}

    def demangle(mangled):
        if mangled[:2] in standard:
            return standard[mangled[:2]] + mangled[2:]
        # Contexts are mangled type names like 5Ablox14BlockAnimationV4KindO:
        # the identifiers are length-prefixed, so take them in order and drop
        # the module name.
        parts, i = [], 0
        while i < len(mangled):
            m = re.match(r'(\d+)', mangled[i:])
            if not m:
                i += 1
                continue
            n = int(m.group(1))
            start = i + len(m.group(1))
            parts.append(mangled[start:start + n])
            i = start + n
        return '.'.join(parts[1:]) or mangled
    if kind == 'topLevel':
        return name
    if kind == 'nominal':
        return demangle(context)
    if kind == 'potentialMember':
        return 'members of ' + demangle(context)
    if kind == 'member':
        return demangle(context) + '.' + name
    return f'{kind} {name}'


def main():
    root, files = sys.argv[1], sys.argv[2:]
    where = {}
    for folder, _, names in os.walk(root):
        for n in names:
            if n.endswith('.swift'):
                where.setdefault(n[:-len('.swift')], os.path.relpath(os.path.join(folder, n), root))

    provides = {}
    uses = {}
    for path in files:
        base = os.path.basename(path)
        stem = re.sub(r'\.swiftdeps(\.yaml)?$', '', base)
        source = where.get(stem, stem + '.swift')
        p, u = set(), set()
        for node in nodes(path):
            kind = node.get('kind')
            if kind in ('sourceFileProvide', 'externalDepend', None):
                continue
            key = (kind, node.get('context', ''), node.get('name', ''))
            if node.get('isProvides') == 'true':
                if node.get('aspect') == 'interface':
                    p.add(key)
            else:
                u.add(key)
        provides[source] = p
        uses[source] = u

    providers = collections.defaultdict(set)
    for source, keys in provides.items():
        for key in keys:
            providers[key].add(source)

    dependents = collections.defaultdict(set)
    blame = collections.defaultdict(lambda: collections.defaultdict(set))
    for user, keys in uses.items():
        for key in keys:
            for source in providers.get(key, ()):
                if source != user:
                    dependents[source].add(user)
                    blame[source][readable(*key)].add(user)

    total = len(provides)
    print(f'{total} files. Files rebuilt, the file, and what most of them use from it:')
    ranked = sorted(provides, key=lambda s: -len(dependents[s]))
    for source in ranked[:40]:
        names = sorted(blame[source].items(), key=lambda kv: -len(kv[1]))[:3]
        why = ', '.join(f'{n} {len(users)}' for n, users in names)
        print(f'{len(dependents[source]):6d}  {source}  ({why})')
    wide = [s for s in provides if len(dependents[s]) >= total // 2]
    print(f'{len(wide)} files rebuild half the app or more after a change to what they declare')


if __name__ == '__main__':
    main()
