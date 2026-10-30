#!/usr/bin/env python3
"""The Lanius grammar as a table for the front end's validator (roadmap step 8).

    python3 formal/tools/grammar_table.py formal/lani/mini/frontend.lani
    python3 formal/tools/grammar_table.py --check formal/lani/mini/frontend.lani

Rewrites the section of the given Lanius file between the lines
`// grammar table begin` and `// grammar table end` from
tables/parse_tables.meta.json (the productions laniusc's parser tables were
generated from, in production id order, which are the ids in laniusc's parse
tree) and the token kinds in crates/laniusc-compiler/src/lexer/tables/tokens.rs.
With --check, fails if the section is stale.

Nonterminals are numbered in order of their first production, so `file` is 0.
A terminal is written as the lexer token kind it stands for: the parser's
contextual retags (`CallLParen`, `LetIdent`, ...) become the lexer kind that
`TokenKind::canonical_lexer_kind` gives them, and `MatchArrow` becomes `Arrow`,
since Lanius writes match arms with `->`, which the parser retags.

Production ids used in the rest of the file as `p_<tag>()`, and lexer token
kinds used as `t_<kind>()` (the kind's name in lower case), get an inline
constant function each.

A file with the lines `// grammar constants begin` and `// grammar constants
end` instead (the extractor, formal/lani/mini/extract.lani) gets only the
constants, named `xp_<tag>()` and `xt_<kind>()`, so that they are distinct
from the front end's.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
META = os.path.join(ROOT, 'tables', 'parse_tables.meta.json')
TOKENS = os.path.join(ROOT, 'crates', 'laniusc-compiler', 'src', 'lexer', 'tables', 'tokens.rs')
BEGIN = '// grammar table begin'
END = '// grammar table end'
CONST_BEGIN = '// grammar constants begin'
CONST_END = '// grammar constants end'
PART = 20


def token_codes():
    text = open(TOKENS).read()
    body = text[text.index('define_token_kinds! {') + len('define_token_kinds! {'):]
    body = body[:body.index('\n}')]
    codes, next_code = {}, None
    for line in body.split('\n'):
        line = line.split('//')[0].strip()
        for entry in filter(None, (e.strip() for e in line.split(','))):
            m = re.fullmatch(r'([A-Za-z]+)(?:\s*=\s*(\d+))?', entry)
            if not m:
                raise SystemExit(f'cannot read token kind {entry!r}')
            code = int(m.group(2)) if m.group(2) else next_code
            codes[m.group(1)] = code
            next_code = code + 1
    return codes


def canonical_map():
    text = open(TOKENS).read()
    body = text[text.index('pub fn canonical_lexer_kind(self) -> Self {'):]
    body = body[body.index('match self {') + len('match self {'):body.index('kind => kind,')]
    out = {}
    for lhs, target in re.findall(r'((?:\|?\s*Self::[A-Za-z]+\s*)+)=>\s*\{?\s*Self::([A-Za-z]+)', body):
        for source in re.findall(r'Self::([A-Za-z]+)', lhs):
            out[source] = target
    return out


def table():
    meta = json.load(open(META))
    prods = meta['productions']
    if meta['start'] != prods[0]['lhs']:
        raise SystemExit('the start symbol is not the left side of production 0')
    nonterms = []
    for p in prods:
        if p['lhs'] not in nonterms:
            nonterms.append(p['lhs'])
    codes, canonical = token_codes(), canonical_map()
    canonical['MatchArrow'] = 'Arrow'

    def sym(s):
        if s in nonterms:
            return f'Nonterm({nonterms.index(s)})'
        name = s.strip("'")
        return f'Term({codes[canonical.get(name, name)]})'

    rows = []
    for k, p in enumerate(prods):
        if p['id'] != k:
            raise SystemExit('production ids are not their positions')
        rhs = 'empty()'
        for s in reversed(p['rhs']):
            rhs = f'cons({sym(s)}, {rhs})'
        rows.append((k, p, f'Rule {{ lhs: {nonterms.index(p["lhs"])}, rhs: {rhs} }}'))
    return rows, nonterms


def wrap(words):
    lines, line = [], '//'
    for w in words:
        if len(line) + len(w) + 2 > 80:
            lines.append(line)
            line = '//'
        line += ' ' + w + ','
    return lines + [line[:-1] + '.']


def constants(rest_of_file, prefix):
    """The inline constant functions for the `{prefix}p_<tag>()` and
    `{prefix}t_<kind>()` calls in rest_of_file."""
    rows, _ = table()
    out = []
    tags = {p['tag']: k for k, p, _ in rows}
    used = sorted(set(re.findall(rf'\b{prefix}p_([a-z0-9_]+)\(\)', rest_of_file)))
    for tag in used:
        if tag not in tags:
            raise SystemExit(f'{prefix}p_{tag}(): no production is tagged {tag}')
        out += [f'// extract: inline', f'fn {prefix}p_{tag}() -> usize {{', f'    return {tags[tag]};', '}', '']
    codes = {name.lower(): code for name, code in token_codes().items()}
    for name in sorted(set(re.findall(rf'\b{prefix}t_([a-z0-9_]+)\(\)', rest_of_file))):
        if name.replace('_', '') not in codes:
            raise SystemExit(f'{prefix}t_{name}(): no token kind is named {name}')
        out += [f'// extract: inline', f'fn {prefix}t_{name}() -> usize {{', f'    return {codes[name.replace("_", "")]};', '}', '']
    return out


def section(rest_of_file):
    rows, nonterms = table()
    parts = [rows[i:i + PART] for i in range(0, len(rows), PART)]
    out = [BEGIN,
           '// Generated by formal/tools/grammar_table.py from tables/parse_tables.meta.json',
           '// and the lexer token kinds; do not edit. Production k of grammar/lanius.bnf is',
           '// element k. Nonterminals:'] + wrap([f'{i} {n}' for i, n in enumerate(nonterms)]) + [
           '']
    for i, part in enumerate(parts):
        out.append(f'// Productions {part[0][0]} to {part[-1][0]}:')
        out += wrap([f'{k} {p["tag"]}' for k, p, _ in part])
        out.append(f'pub fn grammar_part_{i}() -> List<Rule> {{')
        expr = 'empty()'
        for _, _, row in reversed(part):
            expr = f'cons({row},\n        {expr})'
        out.append(f'    return {expr};')
        out += ['}', '']
    chain = f'grammar_part_{len(parts) - 1}()'
    for i in reversed(range(len(parts) - 1)):
        chain = f'concat(grammar_part_{i}(), {chain})'
    out += ['// The productions of grammar/lanius.bnf, by production id.',
            'pub fn grammar() -> List<Rule> {', f'    return {chain};', '}', '']
    out += constants(rest_of_file, '')
    out.append(END)
    return '\n'.join(out)


def main(argv):
    check = '--check' in argv
    paths = [a for a in argv if a != '--check']
    if len(paths) != 1:
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    text = open(paths[0]).read()
    start, end = text.find(BEGIN), text.find(END)
    if start >= 0 and end > start:
        rest = text[:start] + text[end + len(END):]
        new = text[:start] + section(rest) + text[end + len(END):]
    else:
        start, end = text.find(CONST_BEGIN), text.find(CONST_END)
        if start < 0 or end < start:
            raise SystemExit(f'{paths[0]}: no `{BEGIN}` ... `{END}` section')
        rest = text[:start] + text[end + len(CONST_END):]
        body = [CONST_BEGIN, '// Generated by formal/tools/grammar_table.py; do not edit.', ''] + constants(rest, 'x')
        new = text[:start] + '\n'.join(body + [CONST_END]) + text[end + len(CONST_END):]
    if check:
        if new != text:
            print(f'{paths[0]}: the grammar table is stale; rerun formal/tools/grammar_table.py', file=sys.stderr)
            return 1
        return 0
    open(paths[0], 'w').write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
