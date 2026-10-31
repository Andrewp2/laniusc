#!/usr/bin/env python3
"""The certificate that the Lanius grammar has one reading (roadmap step V4).

    python3 formal/tools/grammar_cert.py formal/Lanius/Mini/GrammarCert.lean
    python3 formal/tools/grammar_cert.py --check formal/Lanius/Mini/GrammarCert.lean

Computes, for the grammar the validator checks trees against (the table
grammar_table.py writes, from tables/parse_tables.meta.json), the least sets
`first` and `follow` that formal/Lanius/Mini/Unique.lean's `certOK` accepts:
for each nonterminal, the first two leaf kinds of its trees, and of what
follows it in a tree for `file`, as `Kinds2` values of codes (each token kind
of the grammar gets a code below 80, `>` 1 and `>>` 2; bit 80 * a + b stands
for the pair a b). The computation follows Unique.lean's definitions exactly, so the
Lean kernel's check of `certOK grammar grammarCert` repeats it. Fails if two
productions of one nonterminal are not apart, so a grammar change that makes
the grammar ambiguous, or harder to read than the check allows, is caught
here. With --check, fails if the file is stale.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grammar_table  # noqa: E402

B = 80
MASK = (1 << B) - 1
SHR, GT = 2, 1
# Mirrors Unique.lean's `ruledOut` and the pair `picks` decides.
RULED_OUT = {298}
PICKED_PAIRS = {(48, 49), (84, 85)}


def grammar():
    meta = json.load(open(grammar_table.META))
    prods = meta['productions']
    nonterms = []
    for p in prods:
        if p['lhs'] not in nonterms:
            nonterms.append(p['lhs'])
    codes, canonical = grammar_table.token_codes(), grammar_table.canonical_map()
    canonical['MatchArrow'] = 'Arrow'

    def sym(s):
        if s in nonterms:
            return ('N', nonterms.index(s))
        name = s.strip("'")
        return ('T', codes[canonical.get(name, name)])
    return [(nonterms.index(p['lhs']), [sym(s) for s in p['rhs']]) for p in prods], nonterms


NONE = (False, 0, 0)
EPS = (True, 0, 0)


def row(x, a):
    return (x >> (B * a)) & MASK


def heads(x):
    out = 0
    for a in range(B):
        if row(x, a):
            out |= 1 << a
    return out


def concat(s, t):
    firsts = t[1] | heads(t[2])
    outer = 0
    for a in range(B):
        if s[1] >> a & 1:
            outer |= firsts << (B * a)
    return (s[0] and t[0],
            (t[1] if s[0] else 0) | (s[1] if t[0] else 0),
            (t[2] if s[0] else 0) | s[2] | outer)


def union(s, t):
    return (s[0] or t[0], s[1] | t[1], s[2] | t[2])


def column(k):
    out = 0
    for a in range(B):
        out |= 1 << (B * a + k)
    return out


def widen(x):
    return x | ((x & column(SHR)) >> 1) | ((x & column(GT)) << 1)


def apart(s, t):
    m = B * GT + GT
    return (not (s[0] and t[0]) and not (s[1] & t[1]) and
            not (s[1] >> SHR & 1 and t[2] >> m & 1) and not (t[1] >> SHR & 1 and s[2] >> m & 1) and
            not (s[2] & widen(t[2])) and
            not (row(s[2], SHR) and t[2] >> m & 1) and not (row(t[2], SHR) and s[2] >> m & 1))


def common_prefix(r, s):
    j = 0
    while j < len(r) and j < len(s) and r[j] == s[j]:
        j += 1
    return j


def certificate():
    rules, nonterms = grammar()
    n = len(nonterms)
    allowed = [k for k in range(len(rules)) if k not in RULED_OUT]
    kinds = sorted({x[1] for k in allowed for x in rules[k][1] if x[0] == 'T'} - {13, 44})
    code = {13: GT, 44: SHR}
    for i, kind in enumerate(kinds):
        code[kind] = i + 3
    if len(code) + 1 > B:
        raise SystemExit(f'{len(code)} token kinds do not fit codes below {B}')
    index = [code.get(k, 0) for k in range(max(code) + 1)]
    rules = [(a, [('T', code[x[1]]) if x[0] == 'T' else x for x in rhs]) for a, rhs in rules]
    first = [NONE] * n

    def seq(rhs):
        out = EPS
        for x in reversed(rhs):
            out = concat((False, 1 << x[1], 0) if x[0] == 'T' else first[x[1]], out)
        return out
    changed = True
    while changed:
        changed = False
        for k in allowed:
            a, rhs = rules[k]
            new = union(first[a], seq(rhs))
            if new != first[a]:
                first[a], changed = new, True
    follow = [NONE] * n
    follow[0] = EPS
    changed = True
    while changed:
        changed = False
        for k in allowed:
            a, rhs = rules[k]
            for i, x in enumerate(rhs):
                if x[0] == 'N':
                    new = union(follow[x[1]], concat(seq(rhs[i + 1:]), follow[a]))
                    if new != follow[x[1]]:
                        follow[x[1]], changed = new, True
    bad = []
    for i in allowed:
        for j in allowed:
            if i < j and rules[i][0] == rules[j][0] and (i, j) not in PICKED_PAIRS:
                a, r1, r2 = rules[i][0], rules[i][1], rules[j][1]
                c = common_prefix(r1, r2)
                if not apart(concat(seq(r1[c:]), follow[a]), concat(seq(r2[c:]), follow[a])):
                    bad.append(f'{nonterms[a]}: productions {i} and {j}')
    if bad:
        raise SystemExit('productions not apart:\n  ' + '\n  '.join(bad))
    return index, first, follow, nonterms


def lean(index, first, follow, nonterms):
    def value(s):
        return f'⟨{"true" if s[0] else "false"}, {hex(s[1])}, {hex(s[2])}⟩'
    out = ['import Lanius.Mini.Unique', '',
           '/-! Generated by formal/tools/grammar_cert.py from tables/parse_tables.meta.json; do not edit.',
           'The code of each token kind, the first and follow sets of the grammar the',
           "validator checks trees against, one per nonterminal in `grammar`'s numbering,",
           "and the kernel's check of them (`grammarCert_ok`). -/", '', 'namespace Lanius.Mini', '',
           f'def grammarCodes : List Nat := {index}', '']
    for name, sets in (('grammarFirst', first), ('grammarFollow', follow)):
        out.append(f'def {name} : List Kinds2 := [')
        out += [f'  -- {i} {nonterms[i]}\n  {value(s)}{"," if i + 1 < len(sets) else ""}' for i, s in enumerate(sets)]
        out += [']', '']
    out += ['def grammarCert : Cert := ⟨grammarCodes, grammarFirst, grammarFollow⟩', '',
            'theorem grammarCert_rules : allWith grammarCert.ruleOK 0 grammar = true := by decide +kernel', '',
            'theorem grammarCert_pairs : pairsAll grammarCert.pairOK 0 grammar = true := by decide +kernel', '',
            'theorem grammarCert_ok : certOK grammar grammarCert = true := by',
            '  unfold certOK',
            '  rw [grammarCert_rules, grammarCert_pairs]',
            '  decide +kernel', '',
            'end Lanius.Mini', '']
    return '\n'.join(out)


def main(argv):
    check = '--check' in argv
    paths = [a for a in argv if a != '--check']
    if len(paths) != 1:
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    text = lean(*certificate())
    if check:
        if not os.path.exists(paths[0]) or open(paths[0]).read() != text:
            print(f'{paths[0]}: stale; rerun formal/tools/grammar_cert.py', file=sys.stderr)
            return 1
        return 0
    open(paths[0], 'w').write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
