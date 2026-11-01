"""The verified front end's store rule over every stdlib/ and extended/ .lani file.

    python3 -I formal/tools/store_rule.py [WORKDIR] [--root DIR,..]

The front end does not read `v[i] = value;` (v a local, one index, plain `=`)
when the value can act: when it calls a function or a method, or a host
extern, anywhere in it (frontend.lani's `set_index_eval_of` and `eff_acts`,
SEMANTIC_DECISIONS.md "Front end review fixes"). Core checks i against v's
length before it evaluates the value and laniusc after, so the front end
leaves the whole function unread. The fix is to hoist the value into a let:
`let t = f(); v[i] = t;`.

This is a port of exactly that rule to the source text, so it needs no
laniusc parse: the store is an identifier, one bracketed index and `=` at
the start of a statement; its value acts when it has `name(` or `.name(`
(type arguments `::<..>` allowed), except a variant or type (a capitalised
last segment), the keywords, `slice_stride(x)` (XStride, pure) and the
alloc / dealloc / slice_from_raw_parts calls (which the front end reads as
no value at all, a different gap). Comments, strings and characters are
skipped. Tested against the front end (srcDump Why) on 19 value shapes:
free, method, `T::m` and generic calls, a call nested in arithmetic, a cast,
a match arm, a variant's or a struct literal's field and another slice's
index all act; arithmetic, casts, fields, matches, variants and struct
literals without calls, and a call in the store's own index, do not. (A
`::<T>` call does not parse in the front end.) On the 14 modules of
701eb5283 it names, in their earlier text, exactly the 58 stores that
commit hoisted, and none after.

Prints each offending store as file:line and exits 1 when there is one.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEYWORDS = {'if', 'while', 'match', 'for', 'return', 'as', 'in', 'let', 'loop', 'else', 'fn', 'mut'}
TOKEN = re.compile(r'''
    (?P<space>\s+)
  | (?P<line>//[^\n]*)
  | (?P<block>/\*.*?\*/)
  | (?P<string>"(?:\\.|[^"\\])*")
  | (?P<char>'(?:\\.|[^'\\])')
  | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<number>[0-9][A-Za-z0-9_]*)
  | (?P<punct>::|->|=>|==|!=|<=|>=|&&|\|\||<<=|>>=|[-+*/%&|^]=|<<|>>|.)
''', re.S | re.X)
# Calls the front end reads as no value (unread for another reason).
NO_VALUE = {('alloc', 'allocator', 'alloc'), ('alloc', 'allocator', 'dealloc'), ('slice_from_raw_parts',)}


def tokens(text):
    """(kind, text, line) of each token, comments and literals as one 'lit'."""
    out, line, pos = [], 1, 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        kind = m.lastgroup
        if kind in ('string', 'char', 'number'):
            out.append(('lit', m.group(), line))
        elif kind in ('ident', 'punct'):
            out.append((kind, m.group(), line))
        line += m.group().count('\n')
        pos = m.end()
    return out


def close(toks, i, open_, shut):
    """The index of the token closing the one at i (toks[i] is open_)."""
    depth = 0
    for j in range(i, len(toks)):
        if toks[j][1] == open_:
            depth += 1
        elif toks[j][1] == shut or shut == '>' and toks[j][1] == '>>':
            depth -= len(toks[j][1])
            if depth <= 0:
                return j
    return None


def path_before(toks, i):
    """The path segments ending at the identifier toks[i]."""
    segs = [toks[i][1]]
    while i >= 2 and toks[i - 1][1] == '::' and toks[i - 2][0] == 'ident':
        i -= 2
        segs.insert(0, toks[i][1])
    return tuple(segs), i


def acting_calls(toks, lo, hi):
    """The calls in toks[lo:hi] that act, as text."""
    found = []
    for i in range(lo, hi):
        kind, name, _ = toks[i]
        if kind != 'ident' or name in KEYWORDS:
            continue
        j = i + 1
        if j + 1 < hi and toks[j][1] == '::' and toks[j + 1][1] == '<':
            shut = close(toks, j + 1, '<', '>')
            if shut is None:
                continue
            j = shut + 1
        if j >= hi or toks[j][1] != '(':
            continue
        if i > lo and toks[i - 1][1] == '.':
            found.append('.' + name)
            continue
        segs, first = path_before(toks, i)
        if first > lo and toks[first - 1][1] == '.':
            continue
        if name[0].isupper() or segs == ('slice_stride',) or segs in NO_VALUE:
            continue
        found.append('::'.join(segs))
    return found


def offenders(text):
    """(line, store text, calls) of each index store whose value acts."""
    toks = tokens(text)
    out = []
    for i, (kind, name, line) in enumerate(toks):
        if kind != 'ident' or name in KEYWORDS or i + 1 >= len(toks) or toks[i + 1][1] != '[':
            continue
        if i > 0 and toks[i - 1][1] not in ('{', '}', ';'):
            continue
        shut = close(toks, i + 1, '[', ']')
        if shut is None or shut + 1 >= len(toks) or toks[shut + 1][1] != '=':
            continue
        end, depth = shut + 2, 0
        while end < len(toks) and not (depth == 0 and toks[end][1] == ';'):
            depth += toks[end][1] in '([{' and toks[end][0] == 'punct'
            depth -= toks[end][1] in ')]}' and toks[end][0] == 'punct'
            end += 1
        calls = acting_calls(toks, shut + 2, end)
        if calls:
            out.append((line, ' '.join(t[1] for t in toks[i:end + 1]), calls))
    return out


def main():
    args = sys.argv[1:]
    roots = ['stdlib', 'extended']
    if '--root' in args:
        k = args.index('--root')
        roots = args[k + 1].split(',')
        del args[k:k + 2]
    files, found = 0, []
    for root in roots:
        for top, dirs, names in os.walk(os.path.join(ROOT, root)):
            dirs.sort()
            for name in sorted(names):
                if name.endswith('.lani'):
                    path = os.path.join(top, name)
                    files += 1
                    for line, text, calls in offenders(open(path, encoding='utf-8').read()):
                        found.append(f'{os.path.relpath(path, ROOT)}:{line}: {text}   (calls {", ".join(calls)})')
    for f in found:
        print(f)
    if found:
        print('hoist each value into a let (`let t = f(); v[i] = t;`): the verified front end does not read '
              'an index store whose value calls')
    print(f'{files} .lani files under {", ".join(roots)}, {len(found)} index stores with a call in the value')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
